import Foundation
import NearbyInteraction
import Observation

/// What this phone knows about one nearby badge right now, from every source:
/// its own UWB reading, the server's merged distance (either phone's
/// reading), and Bluetooth. The badge uses it for the edge glows and when its
/// own UWB has nothing for the person it shows.
struct PeerPresence: Equatable {
    var peerId: String
    var name: String
    var isMatch: Bool
    /// Matches only: the pair color and their avatar color.
    var color: String?
    var avatarColor: String?
    /// This phone's own smoothed UWB reading, if fresh.
    var uwbMeters: Double?
    /// The server's merged distance for the pair, its source ("uwb" or "ble") and when it was measured.
    var serverMeters: Double?
    var serverSource: String?
    var serverAt: Date?
    /// Smoothed Bluetooth signal, dBm, if heard recently.
    var bleRSSI: Double?
    /// The server says they are around.
    var inArea: Bool
    /// -1 (left) ... 1 (right) when UWB knows the direction.
    var direction: Double?

    /// Rough meters from a Bluetooth signal (same model as the server's bleEstimateM).
    static func bleEstimate(rssi: Double) -> Double {
        max(0.3, min(60, pow(10, (-59 - rssi) / 22)))
    }

    /// The best distance we have, and whether it is only coarse (Bluetooth).
    func distance(now: Date = Date()) -> (meters: Double, coarse: Bool)? {
        if let m = uwbMeters { return (m, false) }
        if let m = serverMeters, let at = serverAt, now.timeIntervalSince(at) < 3 { return (m, serverSource == "ble") }
        if let rssi = bleRSSI { return (max(2, Self.bleEstimate(rssi: rssi)), true) }
        return nil
    }
}

/// UWB ranging with everyone at the event whose badge is worn full screen,
/// helped by Bluetooth and by the other phone's readings.
///
/// Ranging only runs while this badge is worn full screen and the app is in
/// front (`setActive`). Taking it off, minimizing or closing the app tells the
/// server at once, which drops our distances so the other badge lets go too.
///
/// Every NISession has its own discovery token, so we keep one session per
/// peer: publish that session's token for the peer, and start ranging once the
/// peer has published their token for us. Distances are smoothed on the phone
/// (a median of three, then light smoothing) and sent to the backend a few
/// times a second per peer; the server merges both phones' readings into the
/// pair's distance and sends it back, so one side seeing the other is enough.
///
/// A phone runs only a few NISessions well at once, so we range with
/// `maxSessions` peers: the server's order (the person I'm with, matches in
/// the area, others in the area, ...), nudged by what this phone hears over
/// Bluetooth right now, and sticky (a peer keeps its slot for a while instead
/// of being swapped out with every small change in order). Matches in the
/// area that don't fit yet get a session and a token anyway (`maxPrepared`),
/// so they start ranging the moment a slot frees up.
///
/// Recovery is immediate: a session that lost its peer (timeout, out of view
/// behind people) is run again at once with the same configuration; a
/// suspended one resumes with it; only an invalidated session needs a new
/// token. A session that stays silent while Bluetooth hears the peer close by
/// is woken up again.
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
        /// Has a session and a token, waiting for a UWB slot.
        var prepared = false
        var isMatch = false
        /// This session runs extended UWB (about 50 m).
        var extended = false
        var meters: Double?
        var updatedAt: Date?
        /// The server's merged distance and its source (uwb or ble).
        var serverMeters: Double?
        var serverSource: String?
        /// Bluetooth signal, dBm.
        var bleRSSI: Double?
        var reruns = 0
        var lastError: String?
    }

    enum Status: Equatable {
        case idle, unsupported, ranging, permissionDenied
        case error(String)

        var label: String {
            switch self {
            case .idle: return "Off. Wear the badge full screen to range"
            case .unsupported: return "This iPhone has no Ultra Wideband chip"
            case .ranging: return "Ranging"
            case .permissionDenied: return "Nearby Interaction is off for this app (Settings > Privacy > Nearby Interactions)"
            case .error(let message): return message
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var diagnostics: [String: PeerDiagnostics] = [:]
    /// Badge wearers left out because every UWB slot is taken.
    private(set) var waitingForSlot = 0
    /// What Bluetooth is doing, for the debug panel.
    private(set) var bluetoothLabel = "Off"
    /// At most this many UWB sessions at once (the highest priority peers).
    static let maxSessions = 8
    /// Matches in the area beyond the slots that get a session and token ahead of time.
    static let maxPrepared = 4
    /// A peer keeps its slot at least this long unless someone clearly more important shows up.
    static let minSlotHold: TimeInterval = 8
    /// A running session with no reading this long, while Bluetooth hears the peer near, is run again.
    static let silentRerunAfter: TimeInterval = 4
    var extendedRange: Bool { Self.supportsExtendedRange }
    /// Every smoothed reading (peer id, meters), for the badge's meet moment.
    @ObservationIgnored var onDistance: (@MainActor (String, Double) -> Void)?
    /// Everyone nearby from every source, about twice a second (edge glows, fallbacks).
    @ObservationIgnored var onPresence: (@MainActor ([PeerPresence]) -> Void)?

    @ObservationIgnored private let backend: Backend
    @ObservationIgnored private let beacon = BeaconService()
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var peersTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var bleIdTask: Task<Void, Never>?
    /// The server hands out Bluetooth ids (false on older servers: no reports).
    @ObservationIgnored private var hasBleId = false
    @ObservationIgnored private var sessions: [String: NISession] = [:] // peerId -> session
    @ObservationIgnored private var configs: [String: NINearbyPeerConfiguration] = [:]
    @ObservationIgnored private var runningWith: [String: String] = [:] // peerId -> peer token we run with
    /// A token whose session ended on their side; skipped until they publish a new one (or a while passed).
    @ObservationIgnored private var endedTokens: [String: (token: String, at: Date)] = [:]
    /// Peers with a UWB slot, and since when.
    @ObservationIgnored private var slotSince: [String: Date] = [:]
    /// Sessions paused because their peer lost its slot (kept for a quick comeback).
    @ObservationIgnored private var paused: Set<String> = []
    @ObservationIgnored private var lastReadingAt: [String: Date] = [:]
    @ObservationIgnored private var lastRerunAt: [String: Date] = [:]
    @ObservationIgnored private var extendedPeers: Set<String> = []
    @ObservationIgnored private var lastReport: [String: (at: Date, meters: Double)] = [:]
    @ObservationIgnored private var rawWindow: [String: [Double]] = [:]
    @ObservationIgnored private var smoothed: [String: Double] = [:]
    @ObservationIgnored private var lastPeers: [Peer] = []
    @ObservationIgnored private var peersReceivedAt = Date.distantPast
    @ObservationIgnored private var restarts: [String: [Date]] = [:]
    @ObservationIgnored private var ticks = 0
    /// Badge worn full screen with the app in front.
    @ObservationIgnored private var active = false

    init(backend: Backend) {
        self.backend = backend
    }

    static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    /// Settings > Nearby switch: request extended range (both phones must be iPhone 15 or later).
    static let extendedRangeKey = "nearby.extendedRange"
    static var extendedRangeEnabled: Bool { UserDefaults.standard.bool(forKey: extendedRangeKey) }

    /// How far this phone can sense the peer: about 9 m, 50 m with extended UWB.
    func maxRange(for peerId: String) -> Double {
        extendedPeers.contains(peerId) ? BadgeStore.extendedRange : BadgeStore.standardRange
    }

    /// The furthest "Respond from" makes sense on this phone (Settings > Nearby).
    static var maxRespondRange: Double {
        supportsExtendedRange && extendedRangeEnabled ? BadgeStore.extendedRange : BadgeStore.standardRange
    }

    /// Second generation UWB (iPhone 15 and later) can range further.
    static var supportsExtendedRange: Bool {
        if #available(iOS 17.0, *) {
            return NISession.deviceCapabilities.supportsExtendedDistanceMeasurement
        }
        return false
    }

    /// Signed in: remember who we are. Ranging waits for `setActive(true)`.
    func start(userId: String) {
        guard Self.isSupported else {
            status = .unsupported
            return
        }
        if self.userId != userId { stop() }
        self.userId = userId
        if active { begin() }
    }

    /// Signed out.
    func stop() {
        if active, let userId { Task { [backend] in try? await backend.setRanging(userId: userId, on: false) } }
        tearDown()
        userId = nil
    }

    /// Badge worn full screen and the app in front (true), or not (false).
    func setActive(_ on: Bool) {
        guard on != active else { return }
        active = on
        guard Self.isSupported, let userId else { return }
        if on {
            begin()
        } else {
            tearDown()
            Task { [backend] in try? await backend.setRanging(userId: userId, on: false) }
        }
    }

    private func begin() {
        guard let userId else { return }
        status = .ranging
        peersTask?.cancel()
        peersTask = Task { [backend] in
            do {
                // Tell the server first, so peers includes us on the other phone.
                try await backend.setRanging(userId: userId, on: true)
                for try await peers in backend.peers(userId: userId) {
                    guard self.active else { return }
                    self.peersReceivedAt = Date()
                    self.sync(peers)
                }
            } catch is CancellationError {
            } catch {
                self.status = .error("Peer list stopped: \(error.localizedDescription)")
            }
        }
        beacon.start()
        bleIdTask?.cancel()
        bleIdTask = Task { [backend] in
            // A new Bluetooth id every 15 minutes (the server says when).
            while !Task.isCancelled, self.active {
                let identity = try? await backend.bleId(userId: userId)
                guard !Task.isCancelled, self.active else { return }
                self.hasBleId = identity != nil
                self.beacon.advertise(id: identity?.bleId)
                let left = (identity?.expiresAt ?? 0) / 1000 - Date().timeIntervalSince1970
                try? await Task.sleep(for: .seconds(identity == nil ? 60 : max(30, left - 30)))
            }
        }
        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled, self.active {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, self.active else { return }
                self.tick()
            }
        }
    }

    private func tearDown() {
        peersTask?.cancel()
        peersTask = nil
        tickTask?.cancel()
        tickTask = nil
        bleIdTask?.cancel()
        bleIdTask = nil
        beacon.stop()
        beacon.advertise(id: nil)
        bluetoothLabel = "Off"
        lastPeers = []
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll()
        configs.removeAll()
        runningWith.removeAll()
        endedTokens.removeAll()
        slotSince.removeAll()
        paused.removeAll()
        lastReadingAt.removeAll()
        lastRerunAt.removeAll()
        extendedPeers.removeAll()
        waitingForSlot = 0
        directions.removeAll()
        diagnostics.removeAll()
        smoothed.removeAll()
        rawWindow.removeAll()
        lastReport.removeAll()
        if status == .ranging { status = .idle }
        onPresence?([])
    }

    /// Start over from scratch (debug panel button, or after granting permission).
    func reset() {
        guard userId != nil else { return }
        tearDown()
        restarts.removeAll()
        if active { begin() }
    }

    // MARK: Bluetooth

    /// Heard over Bluetooth recently and not far: "in the area" for this phone.
    private func bleRSSI(_ peer: Peer) -> Double? {
        guard let id = peer.bleId else { return nil }
        return beacon.rssi(for: id)
    }

    /// Twice a second: presence for the badge, waking silent sessions; every
    /// two seconds the Bluetooth report.
    private func tick() {
        ticks += 1
        bluetoothLabel = beacon.statusLabel
        let now = Date()
        // A stale peer list (server slow) still leaves Bluetooth and UWB working locally.
        for peer in lastPeers {
            diagnostics[peer.userId]?.bleRSSI = bleRSSI(peer).map { ($0 * 10).rounded() / 10 }
        }
        wakeSilentSessions(now: now)
        if ticks % 4 == 0, hasBleId, let userId {
            let sightings = beacon.freshSightings(limit: 16, now: now)
            if !sightings.isEmpty {
                Task { [backend] in try? await backend.reportBle(userId: userId, sightings: sightings) }
            }
        }
        // Order can change with Bluetooth alone (someone walked into the area)
        if ticks % 2 == 0 { sync(lastPeers) } else { publishPresence(now: now) }
    }

    /// A running session that has said nothing for a while, while Bluetooth or
    /// the server says the peer is around: run it again (and after a few
    /// tries, start a fresh session with a new token).
    private func wakeSilentSessions(now: Date) {
        for peer in lastPeers where slotSince[peer.userId] != nil && runningWith[peer.userId] != nil {
            let id = peer.userId
            let near = (bleRSSI(peer) ?? -200) >= -80 || peer.inArea == true
            guard near else { continue }
            let quietSince = max(lastReadingAt[id] ?? .distantPast, slotSince[id] ?? .distantPast)
            guard now.timeIntervalSince(quietSince) > Self.silentRerunAfter,
                  now.timeIntervalSince(lastRerunAt[id] ?? .distantPast) > Self.silentRerunAfter else { continue }
            let reruns = diagnostics[id]?.reruns ?? 0
            if reruns >= 3, let session = sessions[id] {
                diagnostics[id]?.reruns = 0
                diagnostics[id]?.lastError = "Silent while nearby; new session"
                restart(session)
            } else {
                rerun(id, reason: "Silent while nearby; ranging again")
            }
        }
    }

    // MARK: Sessions

    /// Run the session again with the configuration it had (after a timeout,
    /// a suspension, or a silence). No token exchange needed.
    private func rerun(_ peerId: String, reason: String) {
        guard let session = sessions[peerId], let config = configs[peerId], runningWith[peerId] != nil else { return }
        lastRerunAt[peerId] = Date()
        diagnostics[peerId]?.reruns += 1
        diagnostics[peerId]?.lastError = reason
        session.run(config)
    }

    /// Local priority: the server's order, nudged by Bluetooth and by who already
    /// ranges well, with a bonus for keeping a slot (fewer swaps, fewer restarts).
    private func score(_ peer: Peer, index: Int, count: Int, now: Date) -> Double {
        var s = peer.priority ?? Double(count - index)
        if let rssi = bleRSSI(peer) { s += rssi >= -75 ? 0.6 : 0.3 }
        if let at = lastReadingAt[peer.userId], now.timeIntervalSince(at) < 3 { s += 0.3 }
        if let since = slotSince[peer.userId] {
            s += now.timeIntervalSince(since) < Self.minSlotHold ? 1.0 : 0.25
        }
        return s
    }

    private func sync(_ peers: [Peer]) {
        guard let userId, active, status != .permissionDenied else { return }
        lastPeers = peers
        let now = Date()
        let ranked = peers.enumerated()
            .map { (peer: $0.element, index: $0.offset, score: score($0.element, index: $0.offset, count: peers.count, now: now)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.peer)
        let chosen = Array(ranked.prefix(Self.maxSessions))
        let chosenIds = Set(chosen.map(\.userId))
        // Matches in the area that don't have a slot yet: token ready ahead of time
        let prepared = ranked.dropFirst(Self.maxSessions)
            .filter { ($0.isMatch ?? false) && ($0.inArea == true || bleRSSI($0) != nil) }
            .prefix(Self.maxPrepared)
        let preparedIds = Set(prepared.map(\.userId))
        waitingForSlot = peers.count - chosen.count

        // Drop sessions for people who left (or are far down the list)
        for (peerId, session) in sessions where !chosenIds.contains(peerId) && !preparedIds.contains(peerId) {
            session.invalidate()
            forget(peerId)
            diagnostics[peerId] = nil
        }
        // Lost the slot but worth keeping: pause, ready to resume
        for peer in prepared {
            var diag = diagnostics[peer.userId] ?? PeerDiagnostics(id: peer.userId, name: peer.name)
            diag.name = peer.name
            diag.isMatch = peer.isMatch ?? true
            diag.prepared = true
            diag.serverMeters = peer.meters
            diag.serverSource = peer.source
            if let session = sessions[peer.userId] {
                if slotSince[peer.userId] != nil, runningWith[peer.userId] != nil {
                    session.pause()
                    paused.insert(peer.userId)
                }
            } else {
                _ = makeSession(for: peer.userId, userId: userId, diag: &diag)
            }
            slotSince[peer.userId] = nil
            diag.running = false
            diagnostics[peer.userId] = diag
        }

        for peer in chosen {
            var diag = diagnostics[peer.userId] ?? PeerDiagnostics(id: peer.userId, name: peer.name)
            diag.name = peer.name
            diag.isMatch = peer.isMatch ?? true
            diag.prepared = false
            diag.serverMeters = peer.meters
            diag.serverSource = peer.source
            if slotSince[peer.userId] == nil { slotSince[peer.userId] = now }
            let session = sessions[peer.userId] ?? makeSession(for: peer.userId, userId: userId, diag: &diag)
            if let ended = endedTokens[peer.userId],
               peer.tokenForMe != ended.token || now.timeIntervalSince(ended.at) > 10 {
                endedTokens[peer.userId] = nil
            }
            let stale = peer.tokenForMe != nil && endedTokens[peer.userId]?.token == peer.tokenForMe
            if let encoded = peer.tokenForMe, !stale,
               runningWith[peer.userId] != encoded || paused.contains(peer.userId) {
                if runningWith[peer.userId] == encoded, let config = configs[peer.userId] {
                    // Back from a pause: same tokens, just resume
                    session.run(config)
                    paused.remove(peer.userId)
                    diag.running = true
                } else if let token = Self.decode(encoded) {
                    let config = NINearbyPeerConfiguration(peerToken: token)
                    // Extended range only works when BOTH phones have the U2 chip
                    // (iPhone 15 and later); asking for it with an older peer
                    // (e.g. iPhone 14, U1) gives no readings at all. Standard
                    // range (~9 m) is the default; extended is off unless
                    // turned on in Settings > Nearby.
                    // The peer's token says whether its chip supports it, so a
                    // mixed pair falls back to standard range instead of going silent.
                    var extended = false
                    if #available(iOS 17.0, *), Self.supportsExtendedRange, Self.extendedRangeEnabled,
                       token.deviceCapabilities.supportsExtendedDistanceMeasurement {
                        config.isExtendedDistanceMeasurementEnabled = true
                        extended = true
                    }
                    if extended { extendedPeers.insert(peer.userId) } else { extendedPeers.remove(peer.userId) }
                    diag.extended = extended
                    session.run(config)
                    configs[peer.userId] = config
                    runningWith[peer.userId] = encoded
                    paused.remove(peer.userId)
                    diag.running = true
                    diag.lastError = nil
                } else {
                    diag.lastError = "Their token could not be read"
                }
            }
            diagnostics[peer.userId] = diag
        }
        publishPresence(now: now)
    }

    /// Everything about a peer's session, gone (they left or lost their place).
    private func forget(_ peerId: String) {
        sessions[peerId] = nil
        configs[peerId] = nil
        runningWith[peerId] = nil
        endedTokens[peerId] = nil
        slotSince[peerId] = nil
        paused.remove(peerId)
        extendedPeers.remove(peerId)
        smoothed[peerId] = nil
        rawWindow[peerId] = nil
        lastReadingAt[peerId] = nil
        directions[peerId] = nil
    }

    private func publishPresence(now: Date) {
        guard let onPresence else { return }
        let received = peersReceivedAt
        let list = lastPeers.map { peer -> PeerPresence in
            let fresh = lastReadingAt[peer.userId].map { now.timeIntervalSince($0) < 2 } ?? false
            return PeerPresence(
                peerId: peer.userId,
                name: peer.name,
                isMatch: peer.isMatch ?? false,
                color: peer.color,
                avatarColor: peer.avatarColor,
                uwbMeters: fresh ? smoothed[peer.userId] : nil,
                serverMeters: peer.meters,
                serverSource: peer.source,
                serverAt: peer.meters == nil ? nil : received.addingTimeInterval(-(peer.ageMs ?? 0) / 1000),
                bleRSSI: bleRSSI(peer),
                inArea: peer.inArea ?? (peer.meters != nil),
                direction: directions[peer.userId]
            )
        }
        onPresence(list)
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
        let now = Date()
        lastReadingAt[peerId] = now
        if diagnostics[peerId]?.reruns != 0 { diagnostics[peerId]?.reruns = 0 }
        if let direction {
            let x = Double(max(-1, min(1, direction.x)))
            if abs((directions[peerId] ?? 0) - x) > 0.05 { directions[peerId] = x }
        }
        // A median of the last three first: in a crowd a body in between makes
        // single readings jump a meter or more (always further). Then light
        // smoothing (UWB jitters by 10 to 30 cm), quick on real changes so the
        // tint follows every step and "together" shows the moment it happens.
        let raw = Double(distance)
        var window = (rawWindow[peerId] ?? []) + [raw]
        if window.count > 3 { window.removeFirst(window.count - 3) }
        rawWindow[peerId] = window
        let median = window.count == 3 ? window.sorted()[1] : window.min() ?? raw
        let value = smoothed[peerId].map { abs(median - $0) > 0.6 ? $0 * 0.15 + median * 0.85 : $0 * 0.4 + median * 0.6 } ?? median
        smoothed[peerId] = value
        diagnostics[peerId]?.meters = value
        diagnostics[peerId]?.updatedAt = now
        onDistance?(peerId, value)

        // Four times a second, or right away on a real change
        if let last = lastReport[peerId],
           now.timeIntervalSince(last.at) < 0.25,
           abs(last.meters - value) < 0.15 { return }
        lastReport[peerId] = (now, value)
        let extended = extendedPeers.contains(peerId)
        Task { [backend] in
            do {
                try await backend.reportDistance(userId: userId, peerId: peerId, meters: value, extended: extended)
            } catch {
                self.diagnostics[peerId]?.lastError = "Report failed: \(error.localizedDescription)"
            }
        }
    }

    /// The peer dropped out of this session.
    fileprivate func handleRemoval(_ session: NISession, reason: NINearbyObject.RemovalReason) {
        guard let peerId = peerId(for: session) else { return }
        // Forget the distance at once, so our badge falls back to the other
        // phone's reading or Bluetooth instead of holding an old number.
        diagnostics[peerId]?.meters = nil
        smoothed[peerId] = nil
        rawWindow[peerId] = nil
        directions[peerId] = nil
        switch reason {
        case .timeout:
            // Out of range or out of view (people in between, phones turned):
            // the session is still good, so run it again right away.
            rerun(peerId, reason: "Lost them for a moment; ranging again")
        case .peerEnded:
            // Their session ended (they restarted it or took the badge off).
            // Keep ours and wait for the new token they publish; running
            // again with the old one gives nothing.
            if let token = runningWith[peerId] { endedTokens[peerId] = (token, Date()) }
            runningWith[peerId] = nil
            diagnostics[peerId]?.running = false
            diagnostics[peerId]?.lastError = "They stopped ranging; waiting for their new token"
            sync(lastPeers)
        @unknown default:
            rerun(peerId, reason: "Lost them; ranging again")
        }
    }

    fileprivate func handleInvalidation(_ session: NISession, error: Error) {
        let peerId = peerId(for: session)
        if let niError = error as? NIError, niError.code == .userDidNotAllow {
            // Restarting can't help until the user turns it back on: stop cleanly.
            status = .permissionDenied
            sessions.values.forEach { $0.invalidate() }
            sessions.removeAll()
            configs.removeAll()
            runningWith.removeAll()
            return
        }
        if let peerId { diagnostics[peerId]?.lastError = error.localizedDescription }
        restart(session)
    }

    /// A session that can't be used again: a fresh one, with a new token, now.
    fileprivate func restart(_ session: NISession) {
        guard let peerId = peerId(for: session) else { return }
        session.invalidate()
        sessions[peerId] = nil
        configs[peerId] = nil
        runningWith[peerId] = nil
        paused.remove(peerId)
        extendedPeers.remove(peerId)
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

    /// A suspension ended (the app came back, another session let go): the
    /// session is still valid, so resume with the same configuration.
    fileprivate func resume(_ session: NISession) {
        guard let peerId = peerId(for: session) else { return }
        if configs[peerId] != nil, runningWith[peerId] != nil, !paused.contains(peerId) {
            rerun(peerId, reason: "Resumed after a suspension")
        } else {
            sync(lastPeers)
        }
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
        Task { @MainActor in self.handleRemoval(session, reason: reason) }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            guard let peerId = self.peerId(for: session) else { return }
            self.diagnostics[peerId]?.lastError = "Suspended by the system"
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in self.resume(session) }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in self.handleInvalidation(session, error: error) }
    }
}
