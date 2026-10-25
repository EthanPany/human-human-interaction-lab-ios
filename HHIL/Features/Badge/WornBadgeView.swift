import SwiftUI
import UIKit

/// The badge you wear: full screen, no chrome, screen stays awake.
/// Vertical or horizontal comes from the available space, so phone rotation
/// and the iPhone Duo's outer display both just work. Pinch in to go back.
struct WornBadgeView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        GeometryReader { geo in
            BadgeView(
                presentation: .worn,
                layout: geo.size.width > geo.size.height ? .horizontal : .vertical
            )
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .gesture(
            MagnifyGesture().onEnded { value in
                if value.magnification < 0.85 { env.badge.takeOff() }
            }
        )
        .accessibilityAction(named: "Take off badge") { env.badge.takeOff() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert(
            "Record this conversation?",
            isPresented: Binding(
                get: { env.badge.pendingConsentConversationId != nil },
                set: { if !$0 { env.badge.declineRecording() } }
            )
        ) {
            Button("Not now", role: .cancel) { env.badge.declineRecording() }
            Button("Record") { env.badge.approveRecording() }
        } message: {
            Text("California mode is on. Make sure the other person agrees before you record.")
        }
    }
}
