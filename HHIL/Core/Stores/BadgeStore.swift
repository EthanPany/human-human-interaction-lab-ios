import Foundation
import Observation

/// The badge: live state from the server, whether it is worn full screen, the
/// "we finally met" moment, and starting or stopping a conversation recording
/// as the state changes.
@MainActor
@Observable
final class BadgeStore {
    private(set) var state: BadgeState = .idle
    /// Full screen "worn" badge vs the window in the Badge tab. Every way in
    /// or out (gestures, the hinge, the system's dismiss) passes through here,
    /// so this is where the wear and take off cues play.
    var isWorn = false {
        didSet {
            guard isWorn != oldValue else { return }
            Feedback.shared.play(isWorn ? .wear : .takeOff)
            cues.isWorn = isWorn
            wornChanged()
        }
    }
    /// Set by the Badge tab while its preview is on screen (for the approach cues).
    var isPreviewVisible = false {
        didSet { cues.isPreviewVisible = isPreviewVisible }
    }
    /// Set while California mode waits for this person's answer about recording.
    var pendingConsentConversationId: String?

    /// 0...1 how close the current match is, from this phone's own UWB reading
    /// when it has a fresh one (every reading, no server round trip), else the
    /// server's. 0 at the pair's respond range, 1 at talking distance.
    private(set) var closeness: Double = 0

    /// Matches in the area when two or more are around at once: up to two,
    /// one glow per side edge, each person keeping their side.
    private(set) var edgeGlows: [EdgeGlow] = []
    /// We came together on Bluetooth alone (UWB had nothing for a while).
    private(set) var togetherEstimated = false
    /// The badge says its "together" is an estimate (the server's or ours).
    var showsEstimated: Bool {
        (state.mode == .talking && state.estimated == true) || (togetherWith != nil && togetherEstimated)
    }

    /// Settings > Demo: people approaching. Pretend people walk up and meet
    /// you, on this phone only: no server writes, no recording.
    var demoMode = false {
        didSet {
            guard demoMode != oldValue else { return }
            if demoMode { startDemo() } else { stopDemo() }
        }
    }

    /// Goes up by one at each "we finally met" moment (the avatars jump to each
    /// other), and again for each newcomer joining a group.
    private(set) var meetCount = 0
    /// Everyone on the badge with me right now, and the meetCount when they
    /// arrived (their own jump in plays once, as they arrive).
    private(set) var arrivals: [String: Int] = [:]
    /// The person we met and are still standing with (nil once we part).
    private(set) var togetherWith: String?
    /// When the current recording actually started (nil when not recording).
    private(set) var recordingStartedAt: Date?
    /// Smoothed microphone level while recording, 0...1, about 20 times a second.
    private(set) var micLevel: Double = 0
    private var meterTask: Task<Void, Never>?

    private let backend: Backend
    private let recorder: ConversationRecorder
    private var task: Task<Void, Never>?
    private var userId: String?
    /// The conversation the server says we are in (recorded or not).
    private var activeConversationId: String?
    /// The task starting the recorder; cancelled if the talk ends first.
    private var recordingTask: Task<Void, Never>?
    /// Waits out a short blip out of the talking state before ending the conversation.
    private var leaveTask: Task<Void, Never>?
    private let cues = BadgeCues()

    /// The meet moment's bookkeeping: who, and when we were last near each other.
    private var metPeerId: String?
    private var lastTogether = Date.distantPast
    private var lastMeetAt = Date.distantPast
    /// Readings in a row on the near (or far) side, per peer, and since when.
    private var streak: (peerId: String, near: Bool, count: Int, since: Date)?
    private var takeOffTask: Task<Void, Never>?
    /// This phone's latest reading of the current peer: meters, its range, when.
    private var localReading: (peerId: String, meters: Double, maxRange: Double, at: Date)?
    /// Conversations this person already answered the recording question for.
    private var consentAnswered: Set<String> = []
    /// Everyone nearby from every source (NearbyService, about twice a second).
    private var presence: [String: PeerPresence] = [:]
    /// Everyone nearby right now (read by the Apple Watch bridge for its list).
    var nearbyPeople: [PeerPresence] { Array(presence.values) }
    /// Which side edge each person glows on (stable while they are around).
    private var edgeSides: [String: EdgeGlow.Side] = [:]
    /// The server reading last used in place of our own UWB, per peer.
    private var lastServerIngest: [String: Date] = [:]
    /// The latest real badge state while the demo runs (shown again after).
    private var realState: BadgeState = .idle
    private var demoTask: Task<Void, Never>?

    // Distance rules: the same numbers as spacetime/src/lib/constants.ts in
    // the parent repo (the server's talking state uses them too).

    /// A badge reacts from the maximum ranging range: standard UWB senses about
    /// 9 m (STANDARD_RANGE_M), extended UWB about 50 m (EXTENDED_RANGE_M).
    static let standardRange = 9.0
    static let extendedRange = 50.0
    /// The lowest "Respond from" in Settings > Nearby (MIN_RESPOND_FROM_M).
    static let minRespondFrom = 2.0
    /// Together at this distance or closer (TALK_DISTANCE_M). Checked on every
    /// local UWB reading, so the moment fires without waiting for the server.
    static let meetDistance = 1.0
    /// Once together, apart only further than this (TALK_EXIT_DISTANCE_M).
    static let apartDistance = 1.5
    /// Back together within this long continues the same encounter (REJOIN_WINDOW_MS).
    static let rejoinWindow: TimeInterval = 5 * 60
    /// "Drop short encounters" threshold (MIN_ENCOUNTER_MS).
    static let minEncounter: TimeInterval = 60

    /// 0 at the respond range, 1 at talking distance, straight line in between
    /// (closenessAt on the server).
    static func closeness(meters: Double, range: Double) -> Double {
        let span = max(0.1, range - meetDistance)
        return max(0, min(1, (range - meters) / span))
    }
    /// UWB readings jump around: this many readings in a row, over at least
    /// this long, confirm we came together (or parted). About a quarter second.
    /// (NearbyService already takes a median of three, so two are enough here.)
    static let confirmReadings = 2
    static let confirmTime: TimeInterval = 0.25
    /// Taking the badge off stops the recording after this long (an accidental
    /// swipe out and straight back in keeps it going).
    static let takeOffGrace: Duration = .seconds(2)
    /// Apart at least this long before meeting the same person counts again
    /// (the meet moment plays again); sooner is the same encounter.
    static let meetAgainAfter: TimeInterval = rejoinWindow
    /// Out of the talking state this long before the conversation really ends.
    static let leaveGrace: Duration = .seconds(6)

    init(backend: Backend, recorder: ConversationRecorder) {
        self.backend = backend
        self.recorder = recorder
    }

    func start(userId: String) {
        self.userId = userId
        task?.cancel()
        task = Task { [backend] in
            do {
                for try await s in backend.badgeState(userId: userId) { await self.apply(s) }
            } catch {
                print("badge state stream ended:", error)
            }
        }
    }

    /// Sign out: stop listening, and close any conversation in progress.
    func stop() {
        realState = .idle
        demoMode = false
        task?.cancel()
        userId = nil
        state = .idle
        cues.reset()
        pendingConsentConversationId = nil
        consentAnswered = []
        localReading = nil
        closeness = 0
        metPeerId = nil
        togetherWith = nil
        arrivals = [:]
        presence = [:]
        edgeGlows = []
        leaveTask?.cancel()
        leaveTask = nil
        if let id = activeConversationId {
            activeConversationId = nil
            Task { await self.finish(id) }
        }
    }

    func wear() { isWorn = true }
    func takeOff() { isWorn = false }

    // MARK: Recording consent (California mode)

    /// Recording starts once the other person said yes too (the server tells us).
    func approveRecording() { answerConsent(true) }

    func declineRecording() { answerConsent(false) }

    private func answerConsent(_ agree: Bool) {
        guard let id = pendingConsentConversationId else { return }
        pendingConsentConversationId = nil
        consentAnswered.insert(id)
        guard let userId else { return }
        Task { [backend] in
            do {
                try await backend.setRecordingConsent(userId: userId, conversationId: id, agree: agree)
            } catch {
                print("recording consent failed:", error)
            }
        }
    }

    /// I said yes and wait for the other person (California mode on either side).
    var waitingForPeerConsent: Bool {
        state.mode == .talking && state.needsConsent && state.myConsent == true && state.peerConsent == nil
    }

    /// The other person said no to recording.
    var peerDeclinedRecording: Bool {
        state.mode == .talking && state.needsConsent && state.peerConsent == false
    }

    // MARK: Meeting

    /// This phone's smoothed UWB distance to a peer (NearbyService, a few times
    /// a second), and how far this phone can sense that peer (9 or 50 m).
    func nearbyDistance(peerId: String, meters: Double, maxRange: Double) {
        guard !demoMode else { return }
        ingest(peerId: peerId, meters: meters, maxRange: maxRange, estimated: false)
    }

    /// Everyone nearby from every source (NearbyService, about twice a second).
    func updatePresence(_ list: [PeerPresence]) {
        guard !demoMode else { return }
        process(list, now: Date())
    }

    private func process(_ list: [PeerPresence], now: Date) {
        presence = Dictionary(list.map { ($0.peerId, $0) }, uniquingKeysWith: { a, _ in a })
        // Our own UWB has nothing for the person the badge shows (they're
        // beside us, out of view, or have no slot): the other phone's reading
        // from the server counts the same, so one side seeing the other is
        // enough for the tint and for "together" (a Bluetooth only "together"
        // comes from the server's strict rule and is marked estimated).
        if let peerId = state.peerId, let p = presence[peerId], p.uwbMeters == nil,
           let meters = p.serverMeters, let at = p.serverAt, now.timeIntervalSince(at) < 2,
           at > (lastServerIngest[peerId] ?? .distantPast).addingTimeInterval(0.05) {
            let ownStale = localReading.map { $0.peerId != peerId || now.timeIntervalSince($0.at) > 1.2 } ?? true
            if ownStale {
                lastServerIngest[peerId] = at
                ingest(peerId: peerId, meters: meters, maxRange: state.respondRangeM ?? Self.standardRange,
                       estimated: p.serverSource == "ble")
            }
        }
        updateEdges(now: now)
    }

    /// Two or more matches in the area: the two strongest glow on the side
    /// edges, one person per side. A person keeps their side while around
    /// (first by where UWB says they are, else by their id).
    private func updateEdges(now: Date) {
        let range = max(Self.minRespondFrom, state.respondRangeM ?? Self.standardRange)
        var items: [(p: PeerPresence, intensity: Double)] = []
        for p in presence.values where p.isMatch && arrivals[p.peerId] == nil {
            let far: (meters: Double, coarse: Bool)? = p.inArea ? (range * 1.5, true) : nil
            guard let d = p.distance(now: now) ?? far else { continue }
            let c = Self.closeness(meters: d.meters, range: range)
            let intensity = d.coarse ? min(0.55, 0.18 + 0.6 * c) : 0.18 + 0.82 * c
            items.append((p, intensity))
        }
        guard items.count >= 2 else {
            if !edgeGlows.isEmpty { edgeGlows = [] }
            return
        }
        // The two strongest; whoever already has a side keeps it
        let top = items.sorted { $0.intensity > $1.intensity }.prefix(2)
            .sorted { (edgeSides[$0.p.peerId] != nil ? 0 : 1) < (edgeSides[$1.p.peerId] != nil ? 0 : 1) }
        var used: Set<EdgeGlow.Side> = []
        var colors: Set<String> = []
        var out: [EdgeGlow] = []
        for item in top {
            let id = item.p.peerId
            var side = edgeSides[id] ?? { () -> EdgeGlow.Side in
                if let x = item.p.direction, abs(x) > 0.15 { return x < 0 ? .leading : .trailing }
                return AvatarStyle.seed(id) % 2 == 0 ? .leading : .trailing
            }()
            if used.contains(side) { side = side.opposite }
            edgeSides[id] = side
            used.insert(side)
            var hex = item.p.avatarColor ?? item.p.color ?? "#FFD55D"
            if colors.contains(hex.uppercased()), let pair = item.p.color { hex = pair }
            colors.insert(hex.uppercased())
            out.append(EdgeGlow(id: id, side: side, colorHex: hex, intensity: (item.intensity * 50).rounded() / 50))
        }
        out.sort { $0.side == .leading && $1.side == .trailing }
        if edgeSides.count > 64 {
            edgeSides = edgeSides.filter { presence[$0.key] != nil }
        }
        if out != edgeGlows { edgeGlows = out }
    }

    /// One distance reading for a peer (ours, the server's merged one, or the demo's).
    private func ingest(peerId: String, meters: Double, maxRange: Double, estimated: Bool) {
        let now = Date()
        if peerId == state.peerId {
            localReading = (peerId, meters, maxRange, now)
            updateCloseness()
        }
        // Which side of the line is this reading on? Between the two distances
        // keeps whatever we were (no flicker right at the threshold).
        let near: Bool? = meters <= Self.meetDistance ? true : (meters > Self.apartDistance ? false : nil)
        if let near {
            if let s = streak, s.peerId == peerId, s.near == near {
                streak = (peerId, near, s.count + 1, s.since)
            } else {
                streak = (peerId, near, 1, now)
            }
        }
        let confirmed = streak.map {
            $0.peerId == peerId && $0.count >= Self.confirmReadings && now.timeIntervalSince($0.since) >= Self.confirmTime
        } ?? false

        if peerId == togetherWith, near == false, confirmed {
            togetherWith = nil
            togetherEstimated = false
            cues.together = false
        }
        if peerId == togetherWith {
            lastTogether = now
            // A real UWB reading inside talking distance: no longer an estimate
            if near == true, !estimated { togetherEstimated = false }
        }
        guard isWorn || (demoMode && isPreviewVisible), peerId == state.peerId, state.mode != .idle,
              near == true, confirmed else { return }
        if togetherWith != peerId { togetherEstimated = estimated }
        meet(peerId)
    }

    /// The tint, glow and heartbeat follow every reading: from the pair's respond
    /// range (the smaller "Respond from", never past what UWB senses) down to 1 m.
    private func updateCloseness() {
        var value = state.closeness
        if state.mode == .talking {
            value = 1
        } else if let r = localReading, r.peerId == state.peerId, Date().timeIntervalSince(r.at) < 2,
                  state.mode == .match || state.mode == .connected {
            let range = min(state.respondRangeM ?? r.maxRange, r.maxRange)
            value = Self.closeness(meters: r.meters, range: range)
        }
        if abs(value - closeness) > 0.004 || (value == 0) != (closeness == 0) { closeness = value }
        cues.approach(closeness: closeness)
    }

    /// The "we finally met" moment, once per meeting: the first time we come
    /// within talking distance, or again after being apart for a while.
    private func meet(_ peerId: String) {
        let now = Date()
        defer { lastTogether = now }
        if peerId == metPeerId || arrivals[peerId] != nil, now.timeIntervalSince(lastTogether) < Self.meetAgainAfter {
            metPeerId = peerId
            togetherWith = peerId // still together (or back after a blip, or another member of the group)
            cues.together = true
            return
        }
        metPeerId = peerId
        togetherWith = peerId
        lastMeetAt = now
        meetCount += 1
        // Let the avatars leap first; the stone lands with them.
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            self.cues.met()
        }
        // A match joins my People now; anyone else once the encounter is kept.
        if let userId, state.isMatch, !demoMode {
            Task { [backend] in
                do {
                    try await backend.markMet(userId: userId, otherId: peerId)
                } catch {
                    print("mark met failed:", error)
                }
            }
        }
    }

    // MARK: State changes

    private func apply(_ new: BadgeState, demo: Bool = false) async {
        // The demo owns the badge while it runs; the real state waits.
        if demoMode, !demo {
            realState = new
            return
        }
        state = new
        cues.update(new)
        if localReading?.peerId != new.peerId { localReading = nil }
        updateCloseness()

        // Someone else is the match now, or nobody: we're not standing together
        // anymore (in a group, the badge may name another member: still together).
        if let together = togetherWith, together != new.peerId,
           !(new.mode == .talking && new.togetherMembers.contains { $0.id == together }) {
            togetherWith = nil
            cues.together = false
        }
        // Talking means we're together, even if this phone has no reading of its own.
        if new.mode == .talking, isWorn || (demo && isPreviewVisible), let peerId = new.peerId {
            if togetherWith != peerId { togetherEstimated = new.estimated == true }
            meet(peerId)
        }
        updateArrivals(new, shown: isWorn || (demo && isPreviewVisible))
        // The demo never records or tells the server anything.
        guard !demo else { return }

        // Only a badge that is worn records (taking it off stops the recording).
        if new.mode == .talking, isWorn, let id = new.conversationId {
            if id == activeConversationId {
                // Back in the same conversation after a blip: keep recording.
                leaveTask?.cancel()
                leaveTask = nil
            } else {
                if let old = activeConversationId { await leave(old) }
                activeConversationId = id
            }
            await updateRecording(new)
        }

        // Left the conversation: after a short grace, stop, upload what we have, trigger follow ups
        if new.mode != .talking, let id = activeConversationId, leaveTask == nil {
            leaveTask = Task {
                try? await Task.sleep(for: Self.leaveGrace)
                guard !Task.isCancelled else { return }
                await self.leave(id)
            }
        }
    }

    /// Record when this person records conversations and, if anyone here has
    /// California mode on, once everyone said yes (asked once per encounter;
    /// coming back within 5 minutes keeps the answers and appends to the
    /// recording). A group records on one phone: when this phone stops being
    /// the one (or a newcomer pauses it for their answer), what it has so far
    /// is uploaded and it stays in the encounter.
    private func updateRecording(_ s: BadgeState) async {
        guard let id = activeConversationId, id == s.conversationId else { return }
        if s.recordConversations, s.needsConsent, s.myConsent == nil, !consentAnswered.contains(id) {
            pendingConsentConversationId = id
        }
        if recordingTask != nil, !s.mayRecord || !s.recordConversations {
            await upload(id, leaving: false)
            return
        }
        guard s.recordConversations, s.mayRecord, recordingTask == nil else { return }
        startRecording()
    }

    /// Group arrivals: the first people are the meet moment (meet above); each
    /// newcomer after them jumps in on their own, with the meet sound, and
    /// mine leaps toward them. People who left drop off the badge.
    private func updateArrivals(_ s: BadgeState, shown: Bool) {
        let members = s.mode == .talking && shown ? s.togetherMembers : []
        guard !members.isEmpty else {
            if togetherWith == nil, !arrivals.isEmpty { arrivals = [:] }
            return
        }
        let ids = Set(members.map(\.id))
        var next = arrivals.filter { ids.contains($0.key) }
        let first = next.isEmpty
        for m in members where next[m.id] == nil {
            if first {
                next[m.id] = meetCount // arrived with the meet moment
            } else {
                meetCount += 1
                next[m.id] = meetCount
                lastMeetAt = Date()
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    self.cues.met()
                }
            }
        }
        if next != arrivals { arrivals = next }
    }

    /// Badge put on or taken off. Off for longer than the grace ends the conversation here.
    private func wornChanged() {
        takeOffTask?.cancel()
        takeOffTask = nil
        guard !isWorn, let id = activeConversationId else { return }
        takeOffTask = Task {
            try? await Task.sleep(for: Self.takeOffGrace)
            guard !Task.isCancelled, !self.isWorn else { return }
            await self.leave(id)
        }
    }

    private func leave(_ id: String) async {
        guard activeConversationId == id else { return }
        activeConversationId = nil
        pendingConsentConversationId = nil
        leaveTask?.cancel()
        leaveTask = nil
        await finish(id)
    }

    /// Stop recording (if any), upload the transcript, trigger follow ups.
    private func finish(_ id: String) async {
        await upload(id, leaving: true)
    }

    /// Stop recording (if any) and upload what it heard. `leaving`: I left the encounter.
    private func upload(_ id: String, leaving: Bool) async {
        var transcript: String?
        let started = recordingStartedAt
        if let starting = recordingTask {
            recordingTask = nil
            starting.cancel()
            await starting.value // start() gives up or completes before we stop
            transcript = await recorder.stop()
        }
        recordingStartedAt = nil
        stopMeter()
        guard leaving || transcript != nil else { return }
        if let userId {
            try? await backend.uploadTranscript(userId: userId, conversationId: id, transcript: transcript,
                                                startedAt: started, leaving: leaving)
        } else {
            try? await backend.finishConversation(id: id, transcript: transcript)
        }
    }

    private func startRecording() {
        #if DEBUG
        if DemoReel.isOn { startDemoRecording(); return }
        #endif
        let recorder = recorder
        // The meet sound plays on the speaker; let it ring out before the mic takes the session.
        let wait = max(0, 1.8 - Date().timeIntervalSince(lastMeetAt))
        recordingTask = Task {
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            await recorder.start()
            if !Task.isCancelled, recorder.isRecording {
                self.recordingStartedAt = Date()
                self.startMeter()
            }
        }
    }

    /// Read the recorder's level 20 times a second and smooth it: quick to
    /// rise when someone speaks, slow to fall, so the meter breathes with voices.
    private func startMeter() {
        meterTask?.cancel()
        let recorder = recorder
        meterTask = Task {
            while !Task.isCancelled, recorder.isRecording {
                let target = Double(recorder.level)
                let k = target > self.micLevel ? 0.55 : 0.18
                let next = self.micLevel + (target - self.micLevel) * k
                if abs(next - self.micLevel) > 0.005 { self.micLevel = next }
                try? await Task.sleep(for: .milliseconds(50))
            }
            self.micLevel = 0
        }
    }

    // MARK: Demo: people approaching (Settings)

    /// A pretend person for the demo.
    private struct DemoPeer {
        let id: String
        let name: String
        let shape: String
        let color: String
        let pairColor: String
        let tag: String
        let keywords: [String]
    }

    /// The demo's timeline, seconds: Maya walks up from 9 m to 0.8 m over 20 s
    /// while Leo comes within 3.5 m and waits (both edges glow), Maya and you
    /// meet, then Leo walks up too and all three of you are together (a group:
    /// he jumps in beside Maya), then both walk away. Then again.
    private static let demoRound: TimeInterval = 50

    private static func demoMayaMeters(_ t: TimeInterval) -> Double? {
        switch t {
        case ..<20: return 9 - (9 - 0.8) * (t / 20)
        case ..<38: return 0.8 + 0.05 * sin(t * 1.3)
        case ..<46: return 0.8 + (9 - 0.8) * ((t - 38) / 8)
        default: return nil
        }
    }

    private static func demoLeoMeters(_ t: TimeInterval) -> Double? {
        switch t {
        case ..<4: return nil
        case ..<16: return 9 - (9 - 3.5) * ((t - 4) / 12)
        case ..<24: return 3.5 + 0.3 * sin(t * 0.8)
        case ..<28: return 3.5 - (3.5 - 0.9) * ((t - 24) / 4)
        case ..<38: return 0.9 + 0.05 * sin(t * 1.1)
        case ..<44: return 0.9 + (9 - 0.9) * ((t - 38) / 6)
        default: return nil
        }
    }

    private func startDemo() {
        realState = state
        resetMeetingForDemo()
        demoTask?.cancel()
        demoTask = Task { await self.runDemo() }
    }

    private func stopDemo() {
        demoTask?.cancel()
        demoTask = nil
        resetMeetingForDemo()
        presence = [:]
        edgeGlows = []
        let real = realState
        Task { await self.apply(real) }
    }

    private func resetMeetingForDemo() {
        localReading = nil
        streak = nil
        togetherWith = nil
        togetherEstimated = false
        metPeerId = nil
        lastTogether = .distantPast
        cues.together = false
        closeness = 0
        cues.approach(closeness: 0)
    }

    private func demoMember(_ p: DemoPeer, joinedAt: Double) -> BadgeMember {
        BadgeMember(id: p.id, name: p.name, avatarShape: p.shape, avatarColor: p.color, matched: true,
                    color: p.pairColor, joinedAt: joinedAt)
    }

    private func demoState(_ p: DemoPeer, mode: BadgeMode, meters: Double) -> BadgeState {
        let c = mode == .talking ? 1 : Self.closeness(meters: meters, range: Self.standardRange)
        var s = BadgeState(
            mode: mode, glow: mode == .talking ? 1 : 0.25 + 0.75 * c, color: p.pairColor, frontTag: p.tag,
            peerId: p.id, peerName: p.name, peerAvatarShape: p.shape, peerAvatarColor: p.color, closeness: c,
            conversationId: nil, recordConversations: false, californiaMode: false, keywords: p.keywords,
            matched: true, respondRangeM: Self.standardRange
        )
        s.meters = meters
        s.distanceSource = "uwb"
        return s
    }

    private func demoPresence(_ p: DemoPeer, meters: Double, direction: Double) -> PeerPresence {
        PeerPresence(peerId: p.id, name: p.name, isMatch: true, color: p.pairColor, avatarColor: p.color,
                     uwbMeters: meters, serverMeters: nil, serverSource: nil, serverAt: nil,
                     bleRSSI: nil, inArea: true, direction: direction)
    }

    /// Ten times a second: move the pretend people, and feed their distances
    /// through the same path real UWB readings take (tint, heartbeat, meet).
    private func runDemo() async {
        var round = 0
        while !Task.isCancelled, demoMode {
            round += 1
            // A new id each round, so the meet moment plays every time.
            let maya = DemoPeer(id: "demo-maya-\(round)", name: "Maya", shape: "blob", color: "#3BB52D",
                                pairColor: "#87D9FB", tag: "Product designer",
                                keywords: ["Agent design", "iOS engineers", "Film photos"])
            let leo = DemoPeer(id: "demo-leo-\(round)", name: "Leo", shape: "flower", color: "#EB8FFF",
                               pairColor: "#FFD60A", tag: "Robotics", keywords: ["Robot arms", "Hackathons"])
            let start = Date()
            var together: Date?
            var leoClose: Date?
            while !Task.isCancelled, demoMode {
                let now = Date()
                let t = now.timeIntervalSince(start)
                if t > Self.demoRound { break }
                let mayaM = Self.demoMayaMeters(t)
                let leoM = Self.demoLeoMeters(t)
                if let m = mayaM {
                    if togetherWith == maya.id { together = together ?? now } else { together = nil }
                    let talking = t < 38 && together.map { now.timeIntervalSince($0) >= 1 } == true
                    var s = demoState(maya, mode: talking ? .talking : .match, meters: m)
                    if talking {
                        // Leo within 1 m for a second while we talk: all three of us are one group
                        if let l = leoM, l <= Self.meetDistance { leoClose = leoClose ?? now } else { leoClose = nil }
                        let leoJoined = leoClose.map { now.timeIntervalSince($0) >= 1 } == true
                        s.members = [demoMember(maya, joinedAt: 1)] + (leoJoined ? [demoMember(leo, joinedAt: 2)] : [])
                        s.group = leoJoined
                    }
                    await apply(s, demo: true)
                    ingest(peerId: maya.id, meters: m, maxRange: Self.standardRange, estimated: false)
                } else if state.mode != .idle {
                    await apply(.idle, demo: true)
                }
                var list: [PeerPresence] = []
                if let m = mayaM { list.append(demoPresence(maya, meters: m, direction: -0.4)) }
                if let m = leoM { list.append(demoPresence(leo, meters: m, direction: 0.5)) }
                process(list, now: now)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    #if DEBUG
    /// Demo reel: no microphone. Shows the recording pill with a meter that
    /// moves like two people talking.
    private func startDemoRecording() {
        let wait = max(0, 1.8 - Date().timeIntervalSince(lastMeetAt))
        recordingTask = Task {
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self.recordingStartedAt = Date()
            self.meterTask?.cancel()
            self.meterTask = Task {
                let start = Date()
                while !Task.isCancelled {
                    let t = Date().timeIntervalSince(start)
                    let syllables = 0.5 + 0.5 * sin(t * 9.1) * sin(t * 3.7 + 1)
                    let phrase = max(0, sin(t * 0.9) + 0.35)
                    let target = min(1, max(0, syllables * phrase * 0.9 + 0.08 * sin(t * 23)))
                    let k = target > self.micLevel ? 0.55 : 0.18
                    self.micLevel += (target - self.micLevel) * k
                    try? await Task.sleep(for: .milliseconds(50))
                }
                self.micLevel = 0
            }
        }
    }
    #endif

    private func stopMeter() {
        meterTask?.cancel()
        meterTask = nil
        micLevel = 0
    }
}
