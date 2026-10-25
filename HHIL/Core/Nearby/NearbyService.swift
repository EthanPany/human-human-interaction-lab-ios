import Foundation
import NearbyInteraction

/// UWB ranging with everyone at the event.
///
/// Every NISession has its own discovery token, so we keep one session per
/// peer: publish that session's token for the peer, and start ranging once the
/// peer has published their token for us. Distances go to the backend about
/// once per second per peer; the server turns them into badge state.
@MainActor
final class NearbyService: NSObject {
    private let backend: Backend
    private var userId: String?
    private var peersTask: Task<Void, Never>?
    private var sessions: [String: NISession] = [:] // peerId -> session
    private var runningWith: [String: String] = [:] // peerId -> peer token we run with
    private var lastReport: [String: Date] = [:]

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
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()
        runningWith.removeAll()
    }

    private func sync(_ peers: [Peer]) {
        guard let userId else { return }
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

    fileprivate func handle(distance: Float, from session: NISession) {
        guard let userId, let peerId = peerId(for: session) else { return }
        let now = Date()
        if let last = lastReport[peerId], now.timeIntervalSince(last) < 1 { return }
        lastReport[peerId] = now
        Task { try? await backend.reportDistance(userId: userId, peerId: peerId, meters: Double(distance)) }
    }

    fileprivate func restart(_ session: NISession) {
        guard let peerId = peerId(for: session) else { return }
        sessions[peerId] = nil
        runningWith[peerId] = nil
        // The next peers update recreates the session and republishes its token.
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
        guard let distance = nearbyObjects.first?.distance else { return }
        Task { @MainActor in self.handle(distance: distance, from: session) }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {}

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in self.restart(session) }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in self.restart(session) }
    }
}
