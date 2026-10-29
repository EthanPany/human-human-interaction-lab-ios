import SwiftUI

@main
struct HHILWatchApp: App {
    @State private var store = WatchStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    store.isActive = phase == .active
                    if phase == .active { store.send(.requestState) }
                }
        }
    }
}

/// Three pages, turned with the Digital Crown: the glance, who is nearby,
/// and the handshake. Questions from the phone (and a felt handshake) come
/// up as a sheet over whichever page is showing.
struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    /// The prompt on screen, so a sheet closing on its own (answered, or
    /// replaced by the next question) never dismisses the next one.
    @State private var presentedId: String?

    var body: some View {
        TabView {
            StatusView()
            NearbyView()
            HandshakeView()
        }
        .tabViewStyle(.verticalPage)
        .background(WatchTheme.background)
        .sheet(item: Binding(
            get: { store.prompt },
            set: { if $0 == nil, let current = store.prompt, current.id == presentedId { store.dismiss(current) } }
        )) { prompt in
            PromptView(prompt: prompt)
                .onAppear { presentedId = prompt.id }
        }
    }
}
