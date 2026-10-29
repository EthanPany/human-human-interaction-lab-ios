import SwiftUI

/// Settings > Apple Watch: is the companion app there and listening, and the
/// handshake share switch. The badge on the lanyard is for others to see; the
/// watch is for the wearer.
struct WatchSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let watch = env.watch
        Section {
            LabeledContent("Status", value: watch.statusLabel)
            if watch.isPaired {
                LabeledContent("App on the watch", value: watch.isWatchAppInstalled ? "Installed" : "Not installed")
                LabeledContent("Reachable", value: watch.isReachable ? "Yes" : "No")
            }
            Toggle("Handshake to share", isOn: Binding(
                get: { watch.handshakeEnabled },
                set: { on in
                    Feedback.shared.play(.toggle(on: on))
                    watch.handshakeEnabled = on
                }
            ))
        } header: {
            Text("Apple Watch")
        } footer: {
            Text("Your watch shows who is near, how far, and whether you are recording, and asks you to approve recording and share requests. With Handshake to share on, shaking hands with someone within 1 m (both watches on, both badges worn) asks on your watch whether to share your card; when you both say yes, you swap what you share by default.")
        }
    }
}
