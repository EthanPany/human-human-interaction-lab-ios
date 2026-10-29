import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.theme) private var theme
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
                Toggle("Drop short encounters", isOn: binding(\.dropShortEncounters, default: true) {
                    ProfilePatch(dropShortEncounters: $0)
                })
            } header: {
                Text("Recording")
            } footer: {
                Text("Recordings are transcribed on your phone for your summary. With California mode on for either of you, both phones ask first and recording starts only when you both agree. Drop short encounters: anything under a minute leaves no record, summary or text.")
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

            // Contact sharing (ShareSettingsView.swift)
            Section {
                NavigationLink {
                    ShareSettingsView()
                } label: {
                    LabeledContent("What I share", value: "\(env.sharing.items.count)")
                }
            } header: {
                Text("Sharing")
            } footer: {
                Text("Links, handles and a QR code you can share with people you meet. Nothing is shared until you choose to.")
            }

            NearbySection()
            LocationSection()
            DemoSection()
            AboutSection()

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
    /// The slider while it moves (saved when let go).
    @State private var respondDraft: Double?

    var body: some View {
        let nearby = env.nearby
        Section {
            LabeledContent("Status", value: nearby.status.label)
            LabeledContent("Bluetooth", value: nearby.bluetoothLabel)
            if nearby.extendedRange {
                Toggle("Extended range", isOn: $extended)
                    .onChange(of: extended) { _, _ in nearby.reset() }
            } else {
                LabeledContent("Range", value: "Standard UWB")
            }
            respondFrom
            if nearby.waitingForSlot > 0 {
                Text("\(nearby.waitingForSlot) more badges are around. Ranging stays with the \(NearbyService.maxSessions) most important (matches first).")
                    .font(theme.caption)
                    .foregroundStyle(theme.inkSecondary)
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
            Text("Bluetooth helps UWB in a crowd: it tells the badge who is in the area (so ranging starts sooner and goes to the right people), and the other phone's reading counts when this one has none. Bluetooth alone never decides you are together unless UWB has nothing for a few seconds and you are right next to each other; the badge then says it is estimated. Respond from sets where your badge starts reacting to a match (glow, tint and the heartbeat), up to the most UWB can sense: about 9 m, or 50 m with extended range. With two badges, the smaller setting counts for both. You are together within 1 m (apart again past 1.5 m); anyone together with you for a moment starts an encounter, match or not, but only matches get the tint. Ranging runs only while the badge is worn full screen; taking it off or leaving the app stops it on both phones at once. Extended range works only when both phones are iPhone 15 or later.")
        }
    }

    /// "Respond from": 2 m up to this phone's maximum. The top of the slider
    /// means the maximum (saved as 50 m, so turning on extended range later
    /// widens it too); the server caps each pair at what their UWB can sense.
    private var respondFrom: some View {
        let top = NearbyService.maxRespondRange
        let saved = env.session.profile?.respondFromM ?? BadgeStore.extendedRange
        let value = min(top, max(BadgeStore.minRespondFrom, respondDraft ?? saved))
        return VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Respond from") {
                Text(value >= top ? "Max, about \(Int(top)) m" : String(format: "%.1f m", value))
                    .font(theme.body.monospacedDigit())
            }
            Slider(
                value: Binding(get: { value }, set: { respondDraft = $0 }),
                in: BadgeStore.minRespondFrom...top,
                step: 0.5,
                onEditingChanged: { editing in
                    guard !editing, let draft = respondDraft else { return }
                    let stored = draft >= top ? BadgeStore.extendedRange : draft
                    Feedback.shared.play(.buttonPress)
                    Task { @MainActor in
                        await env.session.update(ProfilePatch(respondFromM: stored))
                        respondDraft = nil
                    }
                }
            )
            .accessibilityLabel("Respond from")
        }
    }

    private func detail(_ p: NearbyService.PeerDiagnostics) -> String {
        var parts: [String] = []
        parts.append(p.tokenSent ? "token sent" : "no token sent")
        parts.append(p.running ? "ranging" : p.prepared ? "token ready, waiting for a slot" : "waiting for their token")
        parts.append(p.isMatch ? "match" : "not a match")
        if p.extended { parts.append("extended") }
        if let at = p.updatedAt { parts.append("updated \(Int(Date().timeIntervalSince(at)))s ago") }
        if let m = p.serverMeters {
            let source = p.serverSource == "ble" ? "Bluetooth" : "UWB"
            parts.append(String(format: "server %.2f m", m) + " (\(source))")
        }
        if let rssi = p.bleRSSI { parts.append(String(format: "Bluetooth %.0f dBm", rssi)) }
        if p.reruns > 0 { parts.append("woken \(p.reruns)x") }
        if let e = p.lastError { parts.append(e) }
        return parts.joined(separator: " · ")
    }
}

/// Settings > Demo: pretend people walk up to you, for showing the app.
private struct DemoSection: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Section {
            Toggle("Demo: people approaching", isOn: Binding(
                get: { env.badge.demoMode },
                set: { on in
                    Feedback.shared.play(.toggle(on: on))
                    env.badge.demoMode = on
                }
            ))
        } header: {
            Text("Demo")
        } footer: {
            Text("Two pretend matches walk up to you: Maya from 9 m until you meet, Leo stops a few meters away, so both edges of the badge glow. Then they walk off and it starts again. Only on this phone: nothing is sent to the server and nothing is recorded. The badge says Demo while it runs. Wear the badge to show it.")
        }
    }
}
