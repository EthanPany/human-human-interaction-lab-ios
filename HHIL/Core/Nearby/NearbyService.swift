import Foundation
import NearbyInteraction
import Observation

/// UWB ranging with everyone at the event.
///
/// Every NISession has its own discovery token, so we keep one session per
/// peer: publish that session's token for the peer, and start ranging once the
/// peer has published their token for us. Distances go to the backend about
/// once per second per peer; the server turns them into badge state.
@MainActor
@Observable
final class NearbyService: NSObject {
    /// Horizontal direction to each peer, -1 (left) ... 1 (right), when the
    /// phone can tell (they are in front of it). Drives where the avatar looks.
    private(set) var directions: [String: Double] = [:]

    @ObservationIgnored private let backend: Backend
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var peersTask: Task<Void, Never>?
    @ObservationIgnored private var sessions: [String: NISession] = [:] // peerId -> session
    @ObservationIgnored private var runningWith: [String: String] = [:] // peerId -> peer token we run with
    @ObservationIgnored private var lastReport: [String: Date] = [:]
    @ObservationIgnored private var lastPeers: [Peer] = []

    init(backend: Backend) {
        self.backend = backend
    }

    static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    func start(userId: String) {
        guard Self.isSupported else {
            print("Nearby Interaction (UWB) not supported on this device")
            return
        }
        self.userId = userId
        peersTask?.cancel()
        peersTask = Task { [backend] in
            do {
                for try await peers in backend.peers(userId: userId) { self.sync(peers) }
            } catch {
                print("peers stream ended:", error)
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
    }

    private func sync(_ peers: [Peer]) {
        guard let userId else { return }
        lastPeers = peers
        let ids = Set(peers.map(\.userId))

        // Drop sessions for people who left
        for (peerId, session) in sessions where !ids.contains(peerId) {
            session.invalidate()
            sessions[peerId] = nil
            runningWith[peerId] = nil
        }

        for peer in peers {
            let session = sessions[peer.userId] ?? makeSession(for: peer.userId, userId: userId)
            guard let encoded = peer.tokenForMe, runningWith[peer.userId] != encoded,
                  let token = Self.decode(encoded)
            else { continue }
            session.run(NINearbyPeerConfiguration(peerToken: token))
            runningWith[peer.userId] = encoded
        }
    }

    private func makeSession(for peerId: String, userId: String) -> NISession {
        let session = NISession()
        session.delegate = self
        sessions[peerId] = session
        if let token = session.discoveryToken, let encoded = Self.encode(token) {
            Task { try? await backend.uploadToken(userId: userId, peerId: peerId, token: encoded) }
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
        let now = Date()
        if let last = lastReport[peerId], now.timeIntervalSince(last) < 1 { return }
        lastReport[peerId] = now
        Task { try? await backend.reportDistance(userId: userId, peerId: peerId, meters: Double(distance)) }
    }

    fileprivate func restart(_ session: NISession) {
        guard let peerId = peerId(for: session) else { return }
        session.invalidate()
        sessions[peerId] = nil
        runningWith[peerId] = nil
        directions[peerId] = nil
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

    nonisolated func sessionWasSuspended(_ session: NISession) {}

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in self.restart(session) }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in self.restart(session) }
    }
}
