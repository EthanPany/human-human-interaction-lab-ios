import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme
    @State private var provider = AppConfig.backendProvider

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
                Picker("Backend", selection: $provider) {
                    ForEach(BackendProvider.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: provider) { _, new in switchBackend(to: new) }
            } header: {
                Text("Backend")
            } footer: {
                Text("Both run the same app. Each keeps its own accounts, so switching signs you out.")
            }

            Section {
                Button("Sign out", role: .destructive) { env.session.signOut() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Settings")
    }

    /// Accounts don't carry over between providers, so sign out first; the
    /// app then rebuilds itself on the new backend (see HHILApp).
    private func switchBackend(to new: BackendProvider) {
        guard new != env.provider else { return }
        env.session.signOut()
        AppConfig.setBackendProvider(new)
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
