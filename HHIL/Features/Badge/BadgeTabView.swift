import SwiftUI

/// The Badge tab: your badge as a window. Pinch out (or close an iPhone Duo) to wear it.
struct BadgeTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Namespace private var namespace
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        @Bindable var badge = env.badge
        GeometryReader { geo in
            // Keep the phone's proportions so the window is a true preview
            let width = min(geo.size.width - 64, (geo.size.height - 150) * 0.5)
            VStack(spacing: 18) {
                HStack {
                    Text("Badge").font(theme.largeTitle).foregroundStyle(theme.strongInk)
                    Spacer()
                    if env.usingMock {
                        Text("Demo data").font(theme.caption).foregroundStyle(theme.inkSecondary)
                    }
                    IconButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Wear badge") {
                        env.badge.wear()
                    }
                }

                BadgeView(presentation: .window)
                    .frame(width: width, height: width * 2)
                    .clipShape(RoundedRectangle(cornerRadius: theme.badgeCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: theme.badgeCornerRadius).stroke(.white, lineWidth: 6))
                    .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
                    .scaleEffect(min(max(pinch, 0.95), 1.15))
                    .matchedTransitionSource(id: "badge", in: namespace)
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in if value.magnification > 1.15 { env.badge.wear() } }
                    )
                    .accessibilityAction(named: "Wear badge") { env.badge.wear() }

                Text(statusLine)
                    .font(theme.body)
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: statusLine)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.background)
        .fullScreenCover(isPresented: $badge.isWorn) {
            WornBadgeView()
                .navigationTransition(.zoom(sourceID: "badge", in: namespace))
        }
    }

    private var statusLine: String {
        let state = env.badge.state
        let name = state.peerName ?? "Someone"
        switch state.mode {
        case .idle: return "Pinch out to wear it. Your badge reacts when someone you should meet comes close."
        case .match: return "\(name) is nearby. Your avatar is taking on your shared color."
        case .talking: return "You're talking with \(name)."
        case .connected: return "\(name) is in your People. Say hi again!"
        }
    }
}
