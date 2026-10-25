import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme
    @State private var provider = AppConfig.backendProvider
    @AppStorage(Feedback.soundsKey) private var sounds = true
    @AppStorage(Feedback.hapticsKey) private var haptics = true
    @AppStorage(Feedback.soundLevelKey) private var soundLevel = 1.0
    @AppStorage(Feedback.hapticLevelKey) private var hapticLevel = 1.0

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
                Toggle("California mode", isOn: binding(\.californiaMode, default: false) {
                    ProfilePatch(californiaMode: $0)
                })
            } header: {
                Text("Recording")
            } footer: {
                Text("Recordings are transcribed on your phone for your summary. California mode asks before each recording.")
            }

            Section {
                Toggle("Sounds", isOn: $sounds)
                    .onChange(of: sounds) { _, on in Feedback.shared.play(.toggle(on: on)) }
                if sounds {
                    LabeledContent("Volume") {
                        Slider(value: $soundLevel, in: 0...1, onEditingChanged: { editing in
                            if !editing { Feedback.shared.play(.buttonPress) }
                        })
                    }
                }
                Toggle("Haptics", isOn: $haptics)
                    .onChange(of: haptics) { _, on in Feedback.shared.play(.toggle(on: on)) }
                if haptics {
                    LabeledContent("Strength") {
                        Slider(value: $hapticLevel, in: 0...1, onEditingChanged: { editing in
                            if !editing { Feedback.shared.play(.matchAppears) }
                        })
                    }
                }
            } header: {
                Text("Feedback")
            } footer: {
                Text("Soft sounds and taps when you touch your avatar and when a match comes close. The silent switch also mutes the sounds.")
            }

            NearbySection()

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
            set: { newValue in
                Task { @MainActor in
                    Feedback.shared.play(.toggle(on: newValue))
                    await env.session.update(patch(newValue))
                }
            }
        )
    }
}

/// Live view of Ultra Wideband ranging, for testing two phones side by side.
private struct NearbySection: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @AppStorage(NearbyService.extendedRangeKey) private var extended = false

    var body: some View {
        let nearby = env.nearby
        Section {
            LabeledContent("Status", value: nearby.status.label)
            if nearby.extendedRange {
                Toggle("Extended range", isOn: $extended)
                    .onChange(of: extended) { _, _ in nearby.reset() }
            } else {
                LabeledContent("Range", value: "Standard UWB")
            }
            if nearby.diagnostics.isEmpty {
                Text("No other badges worn right now. Ranging runs only while badges are worn full screen, on both phones, signed in as different people.")
                    .font(theme.caption)
                    .foregroundStyle(theme.inkSecondary)
            }
            ForEach(nearby.diagnostics.values.sorted { $0.name < $1.name }) { peer in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(peer.name.isEmpty ? "Someone" : peer.name).font(theme.body.weight(.semibold))
                        Spacer()
                        if let m = peer.meters {
                            Text(String(format: "%.2f m", m)).font(theme.body.monospacedDigit())
                        } else {
                            Text("no distance yet").font(theme.caption).foregroundStyle(theme.inkSecondary)
                        }
                    }
                    Text(detail(peer)).font(theme.caption).foregroundStyle(theme.inkSecondary)
                }
            }
            Button("Restart ranging") { nearby.reset() }
        } header: {
            Text("Nearby (UWB)")
        } footer: {
            Text("A match starts to show within 8 m and you are together within 2 m (confirmed over about half a second). Ranging runs only while the badge is worn full screen; taking it off or leaving the app stops it on both phones at once. Extended range works only when both phones are iPhone 15 or later.")
        }
    }

    private func detail(_ p: NearbyService.PeerDiagnostics) -> String {
        var parts: [String] = []
        parts.append(p.tokenSent ? "token sent" : "no token sent")
        parts.append(p.running ? "ranging" : "waiting for their token")
        if let at = p.updatedAt { parts.append("updated \(Int(Date().timeIntervalSince(at)))s ago") }
        if let e = p.lastError { parts.append(e) }
        return parts.joined(separator: " · ")
    }
}
