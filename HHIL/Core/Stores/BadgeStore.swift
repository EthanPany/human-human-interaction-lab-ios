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
        }
    }
    /// Set by the Badge tab while its preview is on screen (for the approach cues).
    var isPreviewVisible = false {
        didSet { cues.isPreviewVisible = isPreviewVisible }
    }
    /// Set while California mode waits for the user to approve a recording.
    var pendingConsentConversationId: String?

    /// Goes up by one at each "we finally met" moment (the avatars jump to each other).
    private(set) var meetCount = 0
    /// The person we met and are still standing with (nil once we part).
    private(set) var togetherWith: String?
    /// When the current recording actually started (nil when not recording).
    private(set) var recordingStartedAt: Date?

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

    /// Same as TALK_DISTANCE_M in backend/convex/lib/constants.ts. Checked on
    /// every local UWB reading, so the moment fires without waiting for the server.
    static let meetDistance = 3.0
    /// Further than this, we have parted (same as TALK_EXIT_DISTANCE_M).
    static let apartDistance = 4.5
    /// Apart at least this long before meeting the same person counts again.
    static let meetAgainAfter: TimeInterval = 20
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

    func approveRecording() {
        guard pendingConsentConversationId != nil else { return }
        pendingConsentConversationId = nil
        startRecording()
    }

    func declineRecording() {
        pendingConsentConversationId = nil
    }

    // MARK: Meeting

    /// This phone's smoothed UWB distance to a peer (NearbyService, a few times a second).
    func nearbyDistance(peerId: String, meters: Double) {
        if peerId == togetherWith, meters > Self.apartDistance {
            togetherWith = nil
            cues.together = false
        }
        if peerId == togetherWith { lastTogether = Date() }
        guard peerId == state.peerId, state.mode != .idle, meters <= Self.meetDistance else { return }
        meet(peerId)
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
        if let userId {
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

        // Someone else is the match now, or nobody: we're not standing together anymore.
        if let together = togetherWith, together != new.peerId {
            togetherWith = nil
            cues.together = false
        }
        // Talking means we're together, even if this phone has no reading of its own.
        if new.mode == .talking, let peerId = new.peerId { meet(peerId) }

        if new.mode == .talking, let id = new.conversationId {
            if id == activeConversationId {
                // Back in the same conversation after a blip: keep recording.
                leaveTask?.cancel()
                leaveTask = nil
            } else {
                if let old = activeConversationId { await leave(old) }
                activeConversationId = id
                if new.recordConversations {
                    if new.californiaMode { pendingConsentConversationId = id } else { startRecording() }
                }
            }
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
        try? await backend.finishConversation(id: id, transcript: transcript)
    }

    private func startRecording() {
        let recorder = recorder
        // The meet sound plays on the speaker; let it ring out before the mic takes the session.
        let wait = max(0, 1.8 - Date().timeIntervalSince(lastMeetAt))
        recordingTask = Task {
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            await recorder.start()
            if !Task.isCancelled, recorder.isRecording { self.recordingStartedAt = Date() }
        }
    }
}
