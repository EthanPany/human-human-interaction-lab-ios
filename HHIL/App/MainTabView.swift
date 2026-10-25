import SwiftUI

/// Badge, People, Profile. System tab bar (Liquid Glass) kept at the bottom on
/// every device, including the iPhone Duo's inner display.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage("didChooseSetup") private var didChooseSetup = false
    /// Where setup starts, decided once when the profile first loads. Nil: no setup.
    @State private var setupStart: OnboardingFlowView.Step?
    @State private var decidedSetup = false
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if let start = setupStart {
                // Setup takes the whole screen; the tabs come after it
                OnboardingFlowView(start: start) {
                    didChooseSetup = true
                    withAnimation(.easeInOut(duration: 0.35)) { setupStart = nil }
                }
                .transition(.opacity)
            } else if decidedSetup {
                tabs.transition(.opacity)
            } else {
                // A moment while the profile loads, so setup doesn't flash the tabs first
                theme.background.ignoresSafeArea()
            }
        }
        .onChange(of: env.session.needsAvatarSetup, initial: true) { _, needsAvatar in
            // Wait for the profile, then decide once (picking an avatar flips
            // needsAvatarSetup mid flow, which must not end setup).
            guard !decidedSetup, let needsAvatar else { return }
            decide(needsAvatar: needsAvatar)
        }
        .task {
            // Offline: don't wait on the profile forever
            try? await Task.sleep(for: .seconds(4))
            if !decidedSetup { decide(needsAvatar: false) }
        }
    }

    private func decide(needsAvatar: Bool) {
        decidedSetup = true
        if needsAvatar { setupStart = .avatar }
        else if !didChooseSetup { setupStart = .setup }
    }

    private var tabs: some View {
        @Bindable var router = env.router
        return TabView(selection: $router.tab) {
            Tab("Badge", systemImage: "person.text.rectangle", value: AppTab.badge) {
                BadgeTabView()
            }
            Tab("People", systemImage: "person.2", value: AppTab.people) {
                PeopleListView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tabViewStyle(.tabBarOnly)
        .onChange(of: router.tab) { Feedback.shared.play(.tabSwitch) }
        .recordingConsent(isActive: !env.badge.isWorn)
    }
}
