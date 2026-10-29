import Foundation
import Observation
import WatchConnectivity

/// The phone's side of the Apple Watch companion. The phone keeps every piece
/// of state (badge, sharing, recording consent); this service turns it into a
/// compact `WatchState` (WatchShared/WatchPayload.swift) and sends it to the
/// watch, and carries out what the watch asks for (approve recording, answer
/// a share request, a handshake share).
///
/// State goes out as the application context (the latest one waits for the
/// watch app to open) and, while the watch app is on screen, as live messages
/// up to four times a second, only when something changed.
@MainActor
@Observable
final class WatchBridge {
    /// Settings > Apple Watch status.
    private(set) var isSupported = WCSession.isSupported()
    private(set) var isActivated = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false
    /// The handshake in progress or just finished (also shown on the watch).
    private(set) var handshake: WatchHandshake?

    static let handshakeEnabledKey = "watch.handshakeEnabled"
    /// Settings > Apple Watch > Handshake to share (on by default).
    var handshakeEnabled: Bool = UserDefaults.standard.object(forKey: WatchBridge.handshakeEnabledKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(handshakeEnabled, forKey: Self.handshakeEnabledKey) }
    }

    /// Live updates while the watch app is on screen.
    static let tick: Duration = .milliseconds(250)
    /// The application context is refreshed at most this often for distance only changes.
    static let contextInterval: TimeInterval = 2
    /// "Within 1 m" for the handshake, the badge's meet distance.
    static let handshakeDistance = BadgeStore.meetDistance
    /// Someone counts as beside me for a handshake approved this soon after they were.
    static let handshakeGrace: TimeInterval = 10
    /// The server's HANDSHAKE_WINDOW_MS: the other half must come within this long.
    static let handshakeWindow: TimeInterval = 120

    private let backend: Backend
    private let session: SessionStore
    private let badge: BadgeStore
    private let sharing: SharingStore
    private let router: Router
    private let delegate = WatchSessionDelegate()
    private var loop: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?
    private var lastSent: WatchState?
    private var lastContext: WatchState?
    private var lastContextAt = Date.distantPast
    /// When each person was last within handshake distance.
    private var besideAt: [String: (name: String, at: Date)] = [:]

    init(backend: Backend, session: SessionStore, badge: BadgeStore, sharing: SharingStore, router: Router) {
        self.backend = backend
        self.session = session
        self.badge = badge
        self.sharing = sharing
        self.router = router
        delegate.onStatus = { [weak self] in Task { @MainActor in self?.refreshStatus() } }
        delegate.onAction = { [weak self] action in Task { @MainActor in self?.handle(action) } }
        guard isSupported else { return }
        WCSession.default.delegate = delegate
        WCSession.default.activate()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                self?.pump()
            }
        }
    }

    // MARK: Status

    private func refreshStatus() {
        let s = WCSession.default
        isActivated = s.activationState == .activated
        isPaired = s.isPaired
        isWatchAppInstalled = s.isWatchAppInstalled
        isReachable = s.isReachable
        if isReachable { lastSent = nil } // the watch app just opened: send everything again
    }

    var statusLabel: String {
        if !isSupported { return "Not supported" }
        if !isActivated { return "Starting" }
        if !isPaired { return "No Apple Watch paired" }
        if !isWatchAppInstalled { return "App not installed on the watch" }
        return isReachable ? "Connected" : "Installed, app closed"
    }

    // MARK: Sending

    private func pump() {
        guard isActivated, isPaired, isWatchAppInstalled else { return }
        let state = makeState()
        let s = WCSession.default
        let changed = lastSent.map { !$0.sameContent(as: state) } ?? true
        if changed, s.isReachable, let data = state.encoded() {
            s.sendMessage([WatchLink.stateKey: data], replyHandler: nil, errorHandler: nil)
            lastSent = state
        }
        // The context: at once for anything but a moving distance, else every couple of seconds
        let contextChanged = lastContext.map { !$0.sameContent(as: state) } ?? true
        guard contextChanged else { return }
        let important = lastContext.map { !$0.withoutDistances.sameContent(as: state.withoutDistances) } ?? true
        guard important || Date().timeIntervalSince(lastContextAt) >= Self.contextInterval,
              let data = state.encoded() else { return }
        do {
            try s.updateApplicationContext([WatchLink.stateKey: data])
            lastContext = state
            lastContextAt = Date()
        } catch {
            print("watch context failed:", error)
        }
    }

    private func makeState() -> WatchState {
        var w = WatchState()
        w.signedIn = session.isSignedIn
        guard w.signedIn else { return w }
        let profile = session.profile
        let avatar = profile?.avatar ?? AvatarStyle(shape: nil, color: nil)
        w.me = WatchAvatar(name: profile?.name ?? "", shape: avatar.shape.rawValue, color: avatar.colorHex)
        w.worn = badge.isWorn
        w.demo = badge.demoMode
        w.handshakeEnabled = handshakeEnabled
        w.meetCount = badge.meetCount
        w.recordingStartedAt = badge.recordingStartedAt

        let now = Date()
        let s = badge.state
        let presence = badge.nearbyPeople
        func distance(_ id: String) -> (meters: Double, coarse: Bool)? {
            presence.first { $0.peerId == id }?.distance(now: now)
        }
        if s.mode != .idle, let id = s.peerId {
            let d = distance(id) ?? s.meters.map { (meters: $0, coarse: s.distanceSource == "ble") }
            let together = s.mode == .talking || (d.map { !$0.coarse && $0.meters <= Self.handshakeDistance } ?? false)
            w.nearest = WatchPeer(
                id: id, name: s.peerName ?? "Someone", shape: s.peerAvatarShape, color: s.peerAvatarColor,
                pairColor: s.color, isMatch: s.isMatch, meters: d.map { Self.round($0.meters) },
                coarse: d?.coarse ?? false, closeness: (badge.closeness * 20).rounded() / 20,
                together: together, keyword: s.keywords?.first
            )
        }
        let members = s.mode == .talking ? s.togetherMembers : []
        w.groupCount = members.count
        w.nearby = presence.compactMap { p -> WatchPeer? in
            guard let d = p.distance(now: now) else { return nil }
            let member = members.first { $0.id == p.peerId }
            let shape = p.peerId == s.peerId ? s.peerAvatarShape : member?.avatarShape
            return WatchPeer(id: p.peerId, name: p.name.isEmpty ? (member?.displayName ?? "Someone") : p.name,
                             shape: shape, color: p.avatarColor ?? member?.avatarColor, pairColor: p.color,
                             isMatch: p.isMatch, meters: Self.round(d.meters), coarse: d.coarse,
                             together: !d.coarse && d.meters <= Self.handshakeDistance)
        }
        .sorted { ($0.meters ?? .infinity) < ($1.meters ?? .infinity) }
        .prefix(4).map { $0 }

        // Who a handshake would share with: whoever is beside me, closest first
        let beside = ([w.nearest].compactMap { $0 }.filter(\.together) + w.nearby.filter(\.together))
        if let peer = beside.first {
            w.handshakePeer = peer
            for p in beside { besideAt[p.id] = (p.name, now) }
        }
        if besideAt.count > 32 { besideAt = besideAt.filter { now.timeIntervalSince($0.value.at) < 60 } }

        if let id = badge.pendingConsentConversationId {
            w.consent = WatchConsent(conversationId: id, peerName: s.peerName, isGroup: s.isGroup)
        }
        w.requests = sharing.inbox.sorted { $0.createdAt > $1.createdAt }.prefix(3).map { r in
            WatchShareRequest(id: r.id, fromName: r.from?.displayName ?? "Someone", fromColor: r.from?.avatarColor,
                              fromShape: r.from?.avatarShape, isOffer: r.isOffer, items: r.items.map(\.label))
        }
        w.handshake = handshake
        return w
    }

    private static func round(_ meters: Double) -> Double { (meters * 10).rounded() / 10 }

    // MARK: Actions from the watch

    private func handle(_ action: WatchAction) {
        switch action {
        case .requestState:
            lastSent = nil
            lastContext = nil
            pump()
        case let .recordingConsent(id, agree):
            guard badge.pendingConsentConversationId == id else { return }
            if agree { badge.approveRecording() } else { badge.declineRecording() }
        case let .respondShare(id, approve):
            guard let request = sharing.inbox.first(where: { $0.id == id }) else { return }
            Task { await sharing.respond(request, approve: approve) }
        case let .handshake(peerId):
            startHandshake(with: peerId)
        case .cancelHandshake:
            handshakeTask?.cancel()
            setHandshake(nil)
        }
    }

    // MARK: Handshake

    /// The wearer said yes on the watch: send my half of the mutual share.
    /// The first of the two calls waits for the other; the second completes
    /// both. The first caller learns about it from `sharing:with`.
    func startHandshake(with peerId: String) {
        guard let userId = session.userId else { return }
        let name = besideAt[peerId]?.name ?? (badge.state.peerId == peerId ? badge.state.peerName : nil) ?? "them"
        guard handshakeEnabled else {
            setHandshake(WatchHandshake(peerId: peerId, peerName: name, status: .failed,
                                        message: "Handshake sharing is off in Settings on your iPhone."))
            return
        }
        guard let beside = besideAt[peerId], Date().timeIntervalSince(beside.at) < Self.handshakeGrace else {
            setHandshake(WatchHandshake(peerId: peerId, peerName: name, status: .failed,
                                        message: "Stand within 1 m of each other with both badges worn."))
            return
        }
        handshakeTask?.cancel()
        setHandshake(WatchHandshake(peerId: peerId, peerName: name, status: .sending))
        let demo = badge.demoMode
        handshakeTask = Task { [backend] in
            // The demo's people aren't on the server: pretend they approved too
            if demo {
                self.setHandshake(WatchHandshake(peerId: peerId, peerName: name, status: .waiting))
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self.finishHandshake(peerId: peerId, name: name, sharedWithMe: 3, openPerson: false)
                return
            }
            let startedMs = Date().timeIntervalSince1970 * 1000
            do {
                let result = try await backend.shareHandshake(userId: userId, otherId: peerId, itemIds: nil)
                guard !Task.isCancelled else { return }
                if result.status == "complete" {
                    self.finishHandshake(peerId: peerId, name: name, sharedWithMe: result.sharedWithMe, openPerson: true)
                    return
                }
                self.setHandshake(WatchHandshake(peerId: peerId, peerName: name, status: .waiting))
                let deadline = result.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
                    ?? Date().addingTimeInterval(Self.handshakeWindow)
                let done = await Self.waitForTheirHalf(backend: backend, userId: userId, peerId: peerId,
                                                       sinceMs: startedMs - 2000, until: deadline)
                guard !Task.isCancelled else { return }
                if let shared = done {
                    self.finishHandshake(peerId: peerId, name: name, sharedWithMe: shared, openPerson: true)
                } else {
                    self.setHandshake(WatchHandshake(peerId: peerId, peerName: name, status: .expired,
                                                     message: "\(name) didn't approve in time."))
                    self.clearSoon()
                }
            } catch {
                guard !Task.isCancelled else { return }
                Feedback.shared.play(.error)
                self.setHandshake(WatchHandshake(peerId: peerId, peerName: name, status: .failed,
                                                 message: error.localizedDescription))
                self.clearSoon()
            }
        }
    }

    /// Watch `sharing:with` until they shared with me after we started (their
    /// half arrived), or the window closes. Returns how many items I got.
    private static func waitForTheirHalf(backend: Backend, userId: String, peerId: String,
                                         sinceMs: Double, until deadline: Date) async -> Int? {
        await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                do {
                    for try await w in backend.sharing(userId: userId, otherId: peerId) {
                        if let at = w.sharedWithMeAt, at >= sinceMs { return w.theirs.count }
                    }
                } catch {
                    print("handshake wait ended:", error)
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(max(1, deadline.timeIntervalSinceNow)))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func finishHandshake(peerId: String, name: String, sharedWithMe: Int?, openPerson: Bool) {
        setHandshake(WatchHandshake(peerId: peerId, peerName: name, status: .complete, sharedWithMe: sharedWithMe))
        Feedback.shared.play(.saved)
        // Their shared items are on their page in People
        if openPerson { router.showPerson(peerId) }
        clearSoon()
    }

    private func setHandshake(_ h: WatchHandshake?) {
        clearTask?.cancel()
        handshake = h
        pump()
    }

    private func clearSoon() {
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self.handshake = nil
        }
    }

    /// Sign out: drop any handshake and tell the watch.
    func reset() {
        handshakeTask?.cancel()
        handshake = nil
        besideAt = [:]
        lastSent = nil
        lastContext = nil
    }
}

private extension WatchState {
    /// For deciding what is urgent: distances move all the time, the rest doesn't.
    var withoutDistances: WatchState {
        var s = self
        s.nearest?.meters = nil
        s.nearest?.closeness = 0
        s.nearby = s.nearby.map { var p = $0; p.meters = nil; return p }
        return s
    }
}

/// WatchConnectivity calls back on its own queue; this hands everything to the bridge.
private final class WatchSessionDelegate: NSObject, WCSessionDelegate {
    var onStatus: (() -> Void)?
    var onAction: ((WatchAction) -> Void)?

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { print("watch session:", error) }
        onStatus?()
    }

    func sessionDidBecomeInactive(_ session: WCSession) { onStatus?() }

    func sessionDidDeactivate(_ session: WCSession) {
        // Switching watches: activate again for the new one
        WCSession.default.activate()
        onStatus?()
    }

    func sessionWatchStateDidChange(_ session: WCSession) { onStatus?() }
    func sessionReachabilityDidChange(_ session: WCSession) { onStatus?() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receive(message) }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receive(userInfo) }

    private func receive(_ payload: [String: Any]) {
        guard let data = payload[WatchLink.actionKey] as? Data, let action = WatchAction.decode(data) else { return }
        onAction?(action)
    }
}
