import SwiftUI

extension View {
    /// California mode: ask before recording a conversation. Attached to the
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
            Text("California mode is on. Make sure \(env.badge.state.peerName ?? "the other person") agrees before you record.")
        }
    }
}
