import SwiftUI

/// Your profile as modular blocks. Every block is optional: fill it here, or
/// just tell your agent by text and it fills in live.
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var editing = false

    var body: some View {
        let p = env.session.profile
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    identity(p)
                    textBlock("Badge tags", value: p?.tags?.joined(separator: " · "))
                    textBlock("Looking for", value: p?.lookingFor)
                    textBlock("I can help with", value: p?.offers)
                    textBlock("Hobbies", value: p?.hobbies?.joined(separator: " · "), fill: theme.surfaceMuted)
                    textBlock("How to find me", value: p?.appearance)
                }
                .padding(theme.screenPadding)
            }
            .background(theme.background)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editing = true }
                }
            }
            .sheet(isPresented: $editing) { ProfileEditView() }
        }
    }

    private func identity(_ p: UserProfile?) -> some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(p?.displayName ?? "Your name").font(.system(size: 34, weight: .bold))
                    Text(p?.headline ?? "Add a headline").foregroundStyle(theme.inkSecondary)
                }
                Spacer()
                DesignElementPlaceholder(label: "Design element").frame(width: 100, height: 90)
            }
        }
    }

    @ViewBuilder
    private func textBlock(_ title: String, value: String?, fill: Color? = nil) -> some View {
        if let value, !value.isEmpty {
            Card(fill: fill) {
                SectionLabel(text: title)
                Text(value).font(theme.body)
            }
        } else {
            Card(fill: theme.background) {
                SectionLabel(text: title)
                Text("Add it here, or just tell your agent by text.")
                    .foregroundStyle(theme.inkSecondary)
                HStack(spacing: 16) {
                    Button("Add") { editing = true }
                    if let url = AppConfig.agentSMSURL(body: "Here's my \(title.lowercased()):") {
                        Button("Text your agent") { openURL(url) }
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .strokeBorder(theme.placeholderStroke.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
        }
    }
}
