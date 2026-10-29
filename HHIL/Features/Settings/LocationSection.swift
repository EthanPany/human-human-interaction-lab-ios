import SwiftUI

/// Settings > Heads ups: share an approximate location while the app is open
/// (on by default), so the agent texts about a match only when you are both
/// around. Turning it off deletes the last report on the server.
struct LocationSection: View {
    @Environment(AppEnvironment.self) private var env
    @AppStorage(LocationReporter.enabledKey) private var enabled = true

    var body: some View {
        let location = env.location
        Section {
            Toggle("Share approximate location", isOn: $enabled)
                .onChange(of: enabled) { _, on in location.setEnabled(on) }
            if enabled {
                LabeledContent("Status", value: location.status.label)
            }
        } header: {
            Text("Heads ups")
        } footer: {
            Text("Your agent texts you about someone worth meeting only when you are both at the event, within a few hundred meters. Only a rough location is shared while the app is open, and the server deletes it after 15 minutes. Before you meet, the agent describes them only by their badge and a broad topic, never their name.")
        }
    }
}
