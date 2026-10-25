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
        }
    }
}
