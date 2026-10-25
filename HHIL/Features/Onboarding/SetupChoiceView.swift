import SwiftUI

/// After sign in: set up by texting the agent, by hand, or later.
struct SetupChoiceView: View {
    var onDone: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How do you want to set up?").font(theme.title)
            Text("Everything is optional. You can change it anytime.")
                .foregroundStyle(theme.inkSecondary)

            choice(
                "Text with your agent",
                "It asks a few questions at your own pace and fills in your profile."
            ) {
                if let url = AppConfig.agentSMSURL(body: "Hi! Let's set up my badge.") { openURL(url) }
                finish()
            }
            choice("Fill it in myself", "Add your name, badge tags and who you want to meet.") {
                env.router.tab = .profile
                finish()
            }

            Spacer()
            Button("Skip for now") { finish() }
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .task { _ = await ConversationRecorder.requestPermissions() }
    }

    private func choice(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(theme.headline).foregroundStyle(theme.ink)
                Text(detail).font(.subheadline).foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        }
    }

    private func finish() { onDone() }
}
