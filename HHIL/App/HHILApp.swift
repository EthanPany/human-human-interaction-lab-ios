import SwiftUI

@main
struct HHILApp: App {
    @State private var env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(\.theme, .wireframe) // swap in the designers' Theme here
        }
    }
}
