import SwiftUI

@main
struct HHILApp: App {
    @State private var env = AppEnvironment.live()
    @Environment(\.scenePhase) private var scenePhase
    @State private var rangingOff: Task<Void, Never>?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(env.motion)
                .environment(\.theme, .playful) // swap the whole look here
                .tint(Theme.playful.strongInk)
                // The design is light only; in dark mode system placeholder
                // text turns light grey and vanishes on the cream fields.
                .preferredColorScheme(.light)
                // Switching Convex / SpacetimeDB in Settings takes effect at once
                .onReceive(NotificationCenter.default.publisher(for: .backendProviderChanged)) { _ in
                    env = AppEnvironment.live()
                }
                // UWB runs only while the badge is worn full screen with the app in front
                .onChange(of: env.badge.isWorn, initial: true) { _, _ in updateRanging() }
                .onChange(of: scenePhase) { _, _ in updateRanging() }
        }
    }

    /// Leaving the app stops ranging at once. Taking the badge off waits out
    /// BadgeStore.takeOffGrace first, so an accidental swipe out and straight
    /// back in keeps the UWB sessions (and the recording) going.
    private func updateRanging() {
        rangingOff?.cancel()
        let on = env.badge.isWorn && scenePhase == .active
        if on || scenePhase != .active {
            env.nearby.setActive(on)
            return
        }
        rangingOff = Task {
            try? await Task.sleep(for: BadgeStore.takeOffGrace)
            guard !Task.isCancelled, !env.badge.isWorn else { return }
            env.nearby.setActive(false)
        }
    }
}
