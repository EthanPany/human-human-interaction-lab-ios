import SwiftUI

/// Badge, People, Profile. System tab bar (Liquid Glass) kept at the bottom on
/// every device, including the iPhone Duo's inner display.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage("didChooseSetup") private var didChooseSetup = false

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
        .recordingConsent(isActive: !env.badge.isWorn)
        .sheet(isPresented: .constant(!didChooseSetup)) {
            SetupChoiceView { didChooseSetup = true }
                .interactiveDismissDisabled()
        }
    }
}
