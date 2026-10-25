import SwiftUI

/// Badge, People, Profile. System tab bar (Liquid Glass) kept at the bottom on
/// every device, including the iPhone Duo's inner display.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage("didChooseSetup") private var didChooseSetup = false
    /// Where setup starts, decided once when the profile first loads. Nil: no setup.
    @State private var setupStart: OnboardingFlowView.Step?
    @State private var decidedSetup = false

    var body: some View {
        @Bindable var router = env.router
        TabView(selection: $router.tab) {
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
        .sheet(isPresented: Binding(get: { setupStart != nil }, set: { if !$0 { setupStart = nil } })) {
            if let start = setupStart {
                OnboardingFlowView(start: start) {
                    didChooseSetup = true
                    setupStart = nil
                }
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: env.session.needsAvatarSetup, initial: true) { _, needsAvatar in
            // Wait for the profile, then decide once (picking an avatar flips
            // needsAvatarSetup mid flow, which must not close the sheet).
            guard !decidedSetup, let needsAvatar else { return }
            decidedSetup = true
            if needsAvatar { setupStart = .avatar }
            else if !didChooseSetup { setupStart = .setup }
        }
    }
}
