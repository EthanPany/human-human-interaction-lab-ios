import Foundation
import NearbyInteraction
import Observation

/// UWB ranging with everyone at the event whose app is open.
///
/// Every NISession has its own discovery token, so we keep one session per
/// peer: publish that session's token for the peer, and start ranging once the
/// peer has published their token for us. Distances are smoothed on the phone
/// and sent to the backend about twice a second per peer (sooner when they
/// change a lot); the server turns them into badge state.
///
/// Everything it does is visible in `diagnostics` (Settings > Nearby).
@MainActor
@Observable
final class NearbyService: NSObject {
    /// Horizontal direction to each peer, -1 (left) ... 1 (right), when the
    /// phone can tell (they are in front of it). Drives where the avatar looks.
    private(set) var directions: [String: Double] = [:]

    /// What the ranging layer is doing, per peer, for the debug panel.
    struct PeerDiagnostics: Identifiable {
        let id: String
        var name: String
        var tokenSent = false
        var running = false
        var meters: Double?
        var updatedAt: Date?
        var lastError: String?
    }

    enum Status: Equatable {
        case idle, unsupported, ranging, permissionDenied
        case error(String)

        var label: String {
            switch self {
            case .idle: return "Not started"
            case .unsupported: return "This iPhone has no Ultra Wideband chip"
            case .ranging: return "Ranging"
            case .permissionDenied: return "Nearby Interaction is off for this app (Settings > Privacy > Nearby Interactions)"
            case .error(let message): return message
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var diagnostics: [String: PeerDiagnostics] = [:]
    var extendedRange: Bool { Self.supportsExtendedRange }

    @ObservationIgnored private let backend: Backend
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var peersTask: Task<Void, Never>?
    @ObservationIgnored private var sessions: [String: NISession] = [:] // peerId -> session
    @ObservationIgnored private var runningWith: [String: String] = [:] // peerId -> peer token we run with
    @ObservationIgnored private var lastReport: [String: (at: Date, meters: Double)] = [:]
    @ObservationIgnored private var smoothed: [String: Double] = [:]
    @ObservationIgnored private var lastPeers: [Peer] = []
    @ObservationIgnored private var restarts: [String: [Date]] = [:]

    init(backend: Backend) {
        self.backend = backend
    }

    static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    /// Second generation UWB (iPhone 15 and later) can range further.
    static var supportsExtendedRange: Bool {
        if #available(iOS 17.0, *) {
            return NISession.deviceCapabilities.supportsExtendedDistanceMeasurement
        }
        return false
    }

    func start(userId: String) {
        guard Self.isSupported else {
            status = .unsupported
            return
        }
        self.userId = userId
        status = .ranging
        peersTask?.cancel()
        peersTask = Task { [backend] in
            do {
                for try await peers in backend.peers(userId: userId) { self.sync(peers) }
            } catch {
                self.status = .error("Peer list stopped: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        peersTask?.cancel()
        lastPeers = []
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()
        runningWith.removeAll()
        directions.removeAll()
        diagnostics.removeAll()
        smoothed.removeAll()
        if status == .ranging { status = .idle }
    }

    /// Start over from scratch (debug panel button, or after granting permission).
    func reset() {
        guard let userId else { return }
        stop()
        restarts.removeAll()
        start(userId: userId)
    }

    private func sync(_ peers: [Peer]) {
        guard let userId, status != .permissionDenied else { return }
        lastPeers = peers
        let ids = Set(peers.map(\.userId))

        // Drop sessions for people who left
        for (peerId, session) in sessions where !ids.contains(peerId) {
            session.invalidate()
            sessions[peerId] = nil
            runningWith[peerId] = nil
            diagnostics[peerId] = nil
            smoothed[peerId] = nil
        }

        for peer in peers {
            var diag = diagnostics[peer.userId] ?? PeerDiagnostics(id: peer.userId, name: peer.name)
            diag.name = peer.name
            let session = sessions[peer.userId] ?? makeSession(for: peer.userId, userId: userId, diag: &diag)
            if let encoded = peer.tokenForMe, runningWith[peer.userId] != encoded {
                if let token = Self.decode(encoded) {
                    let config = NINearbyPeerConfiguration(peerToken: token)
                    if #available(iOS 17.0, *), Self.supportsExtendedRange {
                        config.isExtendedDistanceMeasurementEnabled = true
                    }
                    session.run(config)
                    runningWith[peer.userId] = encoded
                    diag.running = true
                    diag.lastError = nil
                } else {
                    diag.lastError = "Their token could not be read"
                }
            }
            diagnostics[peer.userId] = diag
        }
    }

    private func makeSession(for peerId: String, userId: String, diag: inout PeerDiagnostics) -> NISession {
        let session = NISession()
        session.delegate = self
        sessions[peerId] = session
        diag.running = false
        if let token = session.discoveryToken, let encoded = Self.encode(token) {
            diag.tokenSent = true
            Task { [backend] in
                do {
                    try await backend.uploadToken(userId: userId, peerId: peerId, token: encoded)
                } catch {
                    self.diagnostics[peerId]?.lastError = "Token upload failed: \(error.localizedDescription)"
                }
            }
        } else {
            diag.lastError = "No discovery token yet"
        }
        return session
    }

    private func peerId(for session: NISession) -> String? {
        sessions.first(where: { $0.value === session })?.key
    }

    fileprivate func handle(distance: Float, direction: SIMD3<Float>?, from session: NISession) {
        guard let userId, let peerId = peerId(for: session) else { return }
        if let direction {
            let x = Double(max(-1, min(1, direction.x)))
            if abs((directions[peerId] ?? 0) - x) > 0.05 { directions[peerId] = x }
        }
        // Light smoothing: UWB readings jitter by 10 to 30 cm
        let raw = Double(distance)
        let value = smoothed[peerId].map { $0 * 0.6 + raw * 0.4 } ?? raw
        smoothed[peerId] = value
        diagnostics[peerId]?.meters = value
        diagnostics[peerId]?.updatedAt = Date()

        // Twice a second, or right away on a big change
        let now = Date()
        if let last = lastReport[peerId],
           now.timeIntervalSince(last.at) < 0.5,
           abs(last.meters - value) < 0.75 { return }
        lastReport[peerId] = (now, value)
        Task { [backend] in
            do {
                try await backend.reportDistance(userId: userId, peerId: peerId, meters: value)
            } catch {
                self.diagnostics[peerId]?.lastError = "Report failed: \(error.localizedDescription)"
            }
        }
    }

    fileprivate func handleInvalidation(_ session: NISession, error: Error) {
        let peerId = peerId(for: session)
        if let niError = error as? NIError, niError.code == .userDidNotAllow {
            // Restarting can't help until the user turns it back on: stop cleanly.
            status = .permissionDenied
            sessions.values.forEach { $0.invalidate() }
            sessions.removeAll()
            runningWith.removeAll()
            return
        }
        if let peerId { diagnostics[peerId]?.lastError = error.localizedDescription }
        restart(session)
    }

    fileprivate func restart(_ session: NISession) {
        guard let peerId = peerId(for: session) else { return }
        session.invalidate()
        sessions[peerId] = nil
        runningWith[peerId] = nil
        directions[peerId] = nil
        diagnostics[peerId]?.running = false

        // Back off if a session keeps dying (at most 5 restarts a minute per peer)
        let now = Date()
        let recent = (restarts[peerId] ?? []).filter { now.timeIntervalSince($0) < 60 } + [now]
        restarts[peerId] = recent
        if recent.count > 5 {
            diagnostics[peerId]?.lastError = "Session keeps failing; retrying in a minute"
            Task {
                try? await Task.sleep(for: .seconds(60))
                self.sync(self.lastPeers)
            }
            return
        }
        // Recreate the session now and republish its token; the peer list
        // itself may not change for a long time.
        sync(lastPeers)
    }

    // MARK: Token coding

    static func encode(_ token: NIDiscoveryToken) -> String? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).base64EncodedString()
    }

    static func decode(_ string: String) -> NIDiscoveryToken? {
        guard let data = Data(base64Encoded: string) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
    }
}

extension NearbyService: NISessionDelegate {
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first, let distance = object.distance else { return }
        let direction = object.direction
        Task { @MainActor in self.handle(distance: distance, direction: direction, from: session) }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        // .peerEnded: they closed the app or lost the session; .timeout: out of range
        Task { @MainActor in
            guard let peerId = self.peerId(for: session) else { return }
            self.diagnostics[peerId]?.lastError = reason == .timeout ? "Out of range" : "They stopped ranging"
            if reason == .peerEnded { self.restart(session) }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {}

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in self.restart(session) }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in self.handleInvalidation(session, error: error) }
    }
}
