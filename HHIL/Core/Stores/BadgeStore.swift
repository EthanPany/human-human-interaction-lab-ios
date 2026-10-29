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

    /// Goes up by one at each "we finally met" moment (the avatars jump to each other).
    private(set) var meetCount = 0
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
    /// this long, confirm we came together (or parted). About half a second.
    static let confirmReadings = 3
    static let confirmTime: TimeInterval = 0.4
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
            cues.together = false
        }
        if peerId == togetherWith { lastTogether = now }
        guard isWorn, peerId == state.peerId, state.mode != .idle, near == true, confirmed else { return }
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
        if peerId == metPeerId, now.timeIntervalSince(lastTogether) < Self.meetAgainAfter {
            togetherWith = peerId // still together (or back after a blip)
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
        if let userId, state.isMatch {
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

    private func apply(_ new: BadgeState) async {
        state = new
        cues.update(new)
        if localReading?.peerId != new.peerId { localReading = nil }
        updateCloseness()

        // Someone else is the match now, or nobody: we're not standing together anymore.
        if let together = togetherWith, together != new.peerId {
            togetherWith = nil
            cues.together = false
        }
        // Talking means we're together, even if this phone has no reading of its own.
        if new.mode == .talking, isWorn, let peerId = new.peerId { meet(peerId) }

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
            updateRecording(new)
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

    /// Record when this person records conversations and, if either of us has
    /// California mode on, once both said yes (asked once per encounter; coming
    /// back within 5 minutes keeps the answers and appends to the recording).
    private func updateRecording(_ s: BadgeState) {
        guard let id = activeConversationId, id == s.conversationId, s.recordConversations else { return }
        if s.needsConsent, s.myConsent == nil, !consentAnswered.contains(id) {
            pendingConsentConversationId = id
        }
        guard s.mayRecord, recordingTask == nil else { return }
        startRecording()
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
        var transcript: String?
        if let starting = recordingTask {
            recordingTask = nil
            starting.cancel()
            await starting.value // start() gives up or completes before we stop
            transcript = await recorder.stop()
        }
        recordingStartedAt = nil
        stopMeter()
        try? await backend.finishConversation(id: id, transcript: transcript)
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
