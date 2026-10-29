import Foundation
import Observation
import WatchConnectivity
import WatchKit
import WidgetKit

/// The watch's copy of the phone's state, the prompts it shows, the taps it
/// plays, and the actions it sends back. The phone (WatchBridge) is the only
/// source of truth; this never talks to the server.
@MainActor
@Observable
final class WatchStore {
    private(set) var state: WatchState
    /// A state has arrived from the phone at least once (this launch or a cached one).
    private(set) var hasState: Bool
    private(set) var isReachable = false
    /// A handshake was felt (or the button tapped) with this person: ask first.
    private(set) var handshakeAsk: WatchPeer?
    /// Shown briefly on the Handshake page ("No one within 1 m", ...).
    private(set) var handshakeNote: String?
    /// Approved here, not yet confirmed by the phone.
    private var localHandshake: WatchHandshake?

    let monitor = HandshakeMonitor()
    /// The app is on screen (handshake listening only then).
    var isActive = false { didSet { updateListening() } }

    private let delegate = WatchSideDelegate()
    private var answeredConsent: Set<String> = []
    private var answeredRequests: Set<String> = []
    private var dismissedHandshakeAt = Date.distantPast
    private var seenRequests: Set<String> = []
    private var approachStep = 0
    private var lastTickAt = Date.distantPast
    /// The last person within 1 m and when (a handshake jiggles the distance).
    private var recentPeer: (peer: WatchPeer, at: Date)?
    private var lastWidget: WatchSnapshot?
    private var lastWidgetReload = Date.distantPast
    private var noteTask: Task<Void, Never>?

    private static let cacheKey = "lastWatchState"
    /// Someone counts as "within 1 m" for a handshake this long after the phones last said so.
    static let handshakeGrace: TimeInterval = 8

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey), let cached = WatchState.decode(data) {
            state = cached
            hasState = true
            seenRequests = Set(cached.requests.map(\.id))
        } else {
            state = WatchState()
            hasState = false
        }
        delegate.onState = { [weak self] data in Task { @MainActor in self?.receive(data) } }
        delegate.onReachable = { [weak self] reachable in
            Task { @MainActor in
                self?.isReachable = reachable
                if reachable { self?.send(.requestState) }
            }
        }
        monitor.onHandshake = { [weak self] in self?.handshakeFelt() }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = delegate
        WCSession.default.activate()
    }

    // MARK: From the phone

    private func receive(_ data: Data) {
        guard let new = WatchState.decode(data), new.sentAt >= state.sentAt || !hasState else { return }
        let old = state
        let first = !hasState
        state = new
        hasState = true
        if !first { playCues(from: old, to: new) } else { seenRequests = Set(new.requests.map(\.id)) }
        if let peer = new.handshakePeer { recentPeer = (peer, Date()) }
        if let h = new.handshake, h.peerId == localHandshake?.peerId {
            localHandshake = nil
            dismissedHandshakeAt = .distantPast // the phone took over: show its status
        }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
        updateListening()
        updateWidgets()
    }

    /// The wrist taps, one meaning each (WKHapticType's round set).
    private func playCues(from old: WatchState, to new: WatchState) {
        let device = WKInterfaceDevice.current()
        let now = Date()
        // A match appears
        if let n = new.nearest, n.isMatch, !n.together, old.nearest?.id != n.id {
            device.play(.directionUp)
            approachStep = Int(n.closeness * 5)
        } else if let n = new.nearest, n.isMatch, !n.together, n.id == old.nearest?.id {
            // Approach: a light tick each fifth of the way closer, at most once a second
            let step = Int(n.closeness * 5)
            if step > approachStep, now.timeIntervalSince(lastTickAt) > 1 {
                device.play(.click)
                lastTickAt = now
            }
            if step > approachStep || step < approachStep - 1 { approachStep = step }
        }
        if new.nearest == nil { approachStep = 0 }
        // We finally met
        if new.meetCount > old.meetCount { device.play(.success) }
        // Recording started
        if old.recordingStartedAt == nil, new.recordingStartedAt != nil { device.play(.start) }
        if old.recordingStartedAt != nil, new.recordingStartedAt == nil { device.play(.stop) }
        // A share request, or the recording question
        let fresh = new.requests.filter { !seenRequests.contains($0.id) }
        if !fresh.isEmpty { device.play(.notification) }
        seenRequests.formUnion(new.requests.map(\.id))
        if let c = new.consent, c.conversationId != old.consent?.conversationId, !answeredConsent.contains(c.conversationId) {
            device.play(.notification)
        }
        // The handshake share
        if let h = new.handshake, h.status != old.handshake?.status || h.peerId != old.handshake?.peerId {
            switch h.status {
            case .complete:
                device.play(.success)
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    device.play(.success)
                }
            case .failed, .expired:
                device.play(.failure)
            case .sending, .waiting:
                break
            }
        }
    }

    // MARK: To the phone

    func send(_ action: WatchAction) {
        guard WCSession.isSupported(), let data = action.encoded() else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        let payload: [String: Any] = [WatchLink.actionKey: data]
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil) { _ in
                // Not delivered live: queue it (the phone gets it when it can)
                if action != .requestState { s.transferUserInfo(payload) }
            }
        } else if action != .requestState {
            s.transferUserInfo(payload)
        }
    }

    // MARK: Prompts

    enum Prompt: Identifiable, Equatable {
        case handshake(peerId: String)
        case consent(WatchConsent)
        case request(WatchShareRequest)

        var id: String {
            switch self {
            case .handshake(let id): return "handshake-\(id)"
            case .consent(let c): return "consent-\(c.conversationId)"
            case .request(let r): return "request-\(r.id)"
            }
        }
    }

    /// What to ask now: a handshake first (it's happening right now), then
    /// the recording question, then share requests.
    var prompt: Prompt? {
        if let ask = handshakeAsk { return .handshake(peerId: ask.id) }
        if let h = shownHandshake { return .handshake(peerId: h.peerId) }
        if let c = state.consent, !answeredConsent.contains(c.conversationId) { return .consent(c) }
        if let r = state.requests.first(where: { !answeredRequests.contains($0.id) }) { return .request(r) }
        return nil
    }

    func dismiss(_ prompt: Prompt) {
        switch prompt {
        case .handshake:
            handshakeAsk = nil
            localHandshake = nil
            dismissedHandshakeAt = Date()
        case .consent(let c):
            answeredConsent.insert(c.conversationId)
        case .request(let r):
            answeredRequests.insert(r.id)
        }
    }

    func answerConsent(_ c: WatchConsent, agree: Bool) {
        answeredConsent.insert(c.conversationId)
        send(.recordingConsent(conversationId: c.conversationId, agree: agree))
        WKInterfaceDevice.current().play(.click)
    }

    func answerRequest(_ r: WatchShareRequest, approve: Bool) {
        answeredRequests.insert(r.id)
        send(.respondShare(requestId: r.id, approve: approve))
        WKInterfaceDevice.current().play(approve ? .success : .click)
    }

    // MARK: Handshake

    /// The handshake to show: the phone's, or mine while the phone hasn't answered yet.
    var shownHandshake: WatchHandshake? {
        if let h = state.handshake, h.updatedAt > dismissedHandshakeAt { return h }
        return localHandshake
    }

    /// Someone within 1 m now, or a moment ago.
    var handshakePeer: WatchPeer? {
        if let p = state.handshakePeer { return p }
        if let r = recentPeer, Date().timeIntervalSince(r.at) < Self.handshakeGrace { return r.peer }
        return nil
    }

    private func updateListening() {
        let busy = handshakeAsk != nil || shownHandshake.map { $0.status == .sending || $0.status == .waiting } == true
        monitor.setListening(isActive && state.handshakeEnabled && state.handshakePeer != nil && !busy)
    }

    /// The detector felt a handshake (or the simulator played one).
    private func handshakeFelt() {
        guard state.handshakeEnabled else { return note("Handshake to share is off on your iPhone.") }
        guard let peer = handshakePeer else { return note("Handshake felt, but no one is within 1 m.") }
        WKInterfaceDevice.current().play(.click)
        ask(peer)
    }

    /// The "Shake hands" button: the same question without the gesture.
    func shakeHandsTapped() {
        guard let peer = handshakePeer else { return note("Stand within 1 m of someone, both badges worn.") }
        ask(peer)
    }

    func simulateHandshake() {
        note("Playing a pretend handshake...")
        monitor.simulate()
    }

    private func ask(_ peer: WatchPeer) {
        handshakeAsk = peer
        updateListening()
    }

    func approveHandshake() {
        guard let peer = handshakeAsk else { return }
        handshakeAsk = nil
        dismissedHandshakeAt = Date()
        let mine = WatchHandshake(peerId: peer.id, peerName: peer.firstName, status: .sending)
        localHandshake = mine
        send(.handshake(peerId: peer.id))
        WKInterfaceDevice.current().play(.click)
        updateListening()
        // No word from the phone: say so instead of spinning forever
        Task {
            try? await Task.sleep(for: .seconds(12))
            guard self.localHandshake == mine else { return }
            self.localHandshake = WatchHandshake(peerId: peer.id, peerName: peer.firstName, status: .failed,
                                                 message: "Your iPhone didn't answer. Open HHIL on it and try again.")
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func declineHandshake() {
        handshakeAsk = nil
        dismissedHandshakeAt = Date()
        updateListening()
    }

    private func note(_ text: String) {
        handshakeNote = text
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self.handshakeNote = nil
        }
    }

    // MARK: Widgets

    /// The Smart Stack and complications read a small snapshot from the app
    /// group. Reload them when what they show really changes (their reload
    /// budget is small): a new person, together or apart, recording, worn,
    /// or the distance moving by a whole band.
    private func updateWidgets() {
        let snap = WatchSnapshot(state)
        snap.save()
        let now = Date()
        func band(_ m: Double?) -> Int { m.map { $0 <= 1 ? 0 : $0 <= 3 ? 1 : $0 <= 6 ? 2 : 3 } ?? -1 }
        let urgent = lastWidget.map {
            $0.peerName != snap.peerName || $0.together != snap.together
                || ($0.recordingStartedAt == nil) != (snap.recordingStartedAt == nil) || $0.worn != snap.worn
        } ?? true
        let moved = lastWidget.map { band($0.meters) != band(snap.meters) } ?? true
        guard urgent || (moved && now.timeIntervalSince(lastWidgetReload) > 60) else { return }
        lastWidget = snap
        lastWidgetReload = now
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// WatchConnectivity calls back on its own queue; this hands it to the store.
private final class WatchSideDelegate: NSObject, WCSessionDelegate {
    var onState: ((Data) -> Void)?
    var onReachable: ((Bool) -> Void)?

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { print("watch session:", error) }
        if let data = session.receivedApplicationContext[WatchLink.stateKey] as? Data { onState?(data) }
        onReachable?(session.isReachable)
    }

    func sessionReachabilityDidChange(_ session: WCSession) { onReachable?(session.isReachable) }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[WatchLink.stateKey] as? Data { onState?(data) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let data = message[WatchLink.stateKey] as? Data { onState?(data) }
    }
}
