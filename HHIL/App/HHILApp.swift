import SwiftUI

@main
struct HHILApp: App {
    @State private var env = AppEnvironment.live()

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
        }
    }
}
