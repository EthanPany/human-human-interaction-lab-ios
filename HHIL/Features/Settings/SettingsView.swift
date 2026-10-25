import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme
    @State private var provider = AppConfig.backendProvider
    @State private var backendURL = AppConfig.convexURLOverride ?? ""
    @State private var spacetimeHost = AppConfig.spacetimeHostOverride ?? ""
    @State private var spacetimeDatabase = AppConfig.spacetimeDatabaseOverride ?? ""
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
                Picker("Backend provider", selection: $provider) {
                    ForEach(BackendProvider.allCases) { Text($0.displayName).tag($0) }
                }
                switch provider {
                case .convex:
                    TextField("https://your-deployment.convex.cloud", text: $backendURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                case .spacetime:
                    TextField(AppConfig.defaultSpacetimeHost, text: $spacetimeHost)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("Database name", text: $spacetimeDatabase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button("Use this backend", action: saveBackend)
            } header: {
                Text("Backend")
            } footer: {
                Text(backendFooter)
            }

            Section {
                Button("Sign out", role: .destructive) { env.session.signOut() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .navigationTitle("Settings")
    }

    private var backendFooter: String {
        if savedURLNote { return "Saved. Quit and reopen the app to switch." }
        let current = env.provider.map { "Now using \($0.displayName)." } ?? "Now using demo data."
        return "\(current) Leave the fields empty to use the build settings. Use them to point at a local backend on your network. Each provider has its own accounts."
    }

    /// Save the choice. Switching providers signs out, since accounts don't carry over.
    private func saveBackend() {
        AppConfig.setConvexURLOverride(backendURL.nilIfBlank)
        AppConfig.setSpacetimeOverride(host: spacetimeHost.nilIfBlank, database: spacetimeDatabase.nilIfBlank)
        AppConfig.setBackendProvider(provider)
        if provider != env.provider { env.session.signOut() }
        savedURLNote = true
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
