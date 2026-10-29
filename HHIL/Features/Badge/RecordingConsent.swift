import SwiftUI

extension View {
    /// California mode (two party consent): when either person has it on, both
    /// phones ask, and recording starts only once both said yes. Attached to the
    /// tabs and to the worn badge (an alert can't show under a full screen cover),
    /// so the prompt appears wherever the person is.
    func recordingConsent(isActive: Bool = true) -> some View {
        modifier(RecordingConsentAlert(isActive: isActive))
    }
}

private struct RecordingConsentAlert: ViewModifier {
    var isActive: Bool
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.alert(
            "Record this conversation?",
            isPresented: Binding(
                get: { isActive && env.badge.pendingConsentConversationId != nil },
                set: { if !$0 && isActive { env.badge.declineRecording() } }
            )
        ) {
            Button("Not now", role: .cancel) { env.badge.declineRecording() }
            Button("Record") { env.badge.approveRecording() }
        } message: {
            Text(env.badge.state.isGroup
                 ? "California mode is on for someone here. Everyone in the group is asked; recording starts only when you all agree."
                 : "California mode is on for one of you. \(env.badge.state.peerName ?? "The other person") is asked too; recording starts only when you both agree.")
        }
    }
}
