import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme
    @State private var backendURL = AppConfig.convexURLOverride ?? ""
    @State private var savedURLNote = false

    var body: some View {
        let p = env.session.profile
        Form {
            Section("Account") {
                LabeledContent("Phone number", value: p?.phone ?? "")
                if let url = AppConfig.agentSMSURL(body: "Hi") {
                    Button("Text your agent") { openURL(url) }
                }
            }

            Section {
                Toggle("Record conversations", isOn: binding(\.recordConversations, default: true) {
                    ProfilePatch(recordConversations: $0)
                })
                Toggle("California mode", isOn: binding(\.californiaMode, default: true) {
                    ProfilePatch(californiaMode: $0)
                })
            } header: {
                Text("Recording")
            } footer: {
                Text("Recordings are transcribed on your phone for your summary. California mode asks before each recording.")
            }

            Section {
                TextField("https://your-deployment.convex.cloud", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                Button("Use this backend") {
                    AppConfig.setConvexURLOverride(backendURL.nilIfBlank)
                    savedURLNote = true
                }
            } header: {
                Text("Backend")
            } footer: {
                Text(savedURLNote
                     ? "Saved. Quit and reopen the app to switch."
                     : "Leave empty to use the build setting. Use this to point at a local backend on your network.")
            }

            Section {
                Button("Sign out", role: .destructive) { env.session.signOut() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Settings")
    }

    /// A toggle bound to a profile flag that saves to the backend on change.
    private func binding(
        _ key: KeyPath<UserProfile, Bool?>,
        default value: Bool,
        patch: @escaping (Bool) -> ProfilePatch
    ) -> Binding<Bool> {
        Binding(
            get: { env.session.profile?[keyPath: key] ?? value },
            set: { newValue in Task { await env.session.update(patch(newValue)) } }
        )
    }
}
