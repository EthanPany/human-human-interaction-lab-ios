import Foundation
import Observation

/// The badge: live state from the server, whether it is worn full screen, and
/// starting or stopping a conversation recording as the state changes.
@MainActor
@Observable
final class BadgeStore {
    private(set) var state: BadgeState = .idle
    /// Full screen "worn" badge vs the window in the Badge tab.
    var isWorn = false
    /// Set while California mode waits for the user to approve a recording.
    var pendingConsentConversationId: String?

    private let backend: Backend
    private let recorder: ConversationRecorder
    private var task: Task<Void, Never>?
    /// The conversation the server says we are in (recorded or not).
    private var activeConversationId: String?
    private var isRecordingActive = false

    init(backend: Backend, recorder: ConversationRecorder) {
        self.backend = backend
        self.recorder = recorder
    }

    func start(userId: String) {
        task?.cancel()
        task = Task { [backend] in
            do {
                for try await s in backend.badgeState(userId: userId) { await self.apply(s) }
            } catch {
                print("badge state stream ended:", error)
            }
        }
    }

    func stop() {
        task?.cancel()
        state = .idle
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

    // MARK: State changes

    private func apply(_ new: BadgeState) async {
        state = new

        // Entered a new conversation
        if new.mode == .talking, let id = new.conversationId, id != activeConversationId {
            activeConversationId = id
            if new.recordConversations {
                if new.californiaMode { pendingConsentConversationId = id } else { startRecording() }
            }
        }

        // Left the conversation: stop, upload what we have, trigger follow ups
        if new.mode != .talking, let id = activeConversationId {
            activeConversationId = nil
            pendingConsentConversationId = nil
            var transcript: String?
            if isRecordingActive {
                isRecordingActive = false
                transcript = await recorder.stop()
            }
            try? await backend.finishConversation(id: id, transcript: transcript)
        }
    }

    private func startRecording() {
        isRecordingActive = true
        let recorder = recorder
        Task { await recorder.start() }
    }
}
