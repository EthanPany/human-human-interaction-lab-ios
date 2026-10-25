import SwiftUI

/// After sign in: set up by texting the agent, by hand, or later.
struct SetupChoiceView: View {
    var onDone: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How do you want to set up?").font(theme.title).foregroundStyle(theme.strongInk)
            Text("Everything is optional. You can change it anytime.")
                .font(theme.body)
                .foregroundStyle(theme.inkSecondary)

            choice("Text with your agent", "It asks a few questions at your own pace and fills in your profile.",
                   fill: theme.yellow, icon: "message.fill") {
                if let url = AppConfig.agentSMSURL(body: "Hi! Let's set up my badge.") { openURL(url) }
                onDone()
            }
            choice("Fill it in myself", "Add your name, interests and who you want to meet.",
                   fill: theme.blue, icon: "pencil") {
                env.router.tab = .profile
                onDone()
            }

            Spacer()
            Button("Skip for now") { onDone() }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(theme.background)
        .task { _ = await ConversationRecorder.requestPermissions() }
    }

    private func choice(_ title: String, _ detail: String, fill: Color, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                IconButtonLabel(systemImage: icon)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(theme.headline).foregroundStyle(theme.strongInk)
                    Text(detail).font(theme.body).foregroundStyle(theme.ink)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(fill, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        }
        .buttonStyle(PressScaleStyle())
    }
}
