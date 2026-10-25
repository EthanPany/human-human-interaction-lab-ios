import SwiftUI

/// The Badge tab: your badge as a window. Pinch out (or close an iPhone Duo) to wear it.
struct BadgeTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Namespace private var namespace
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        @Bindable var badge = env.badge
        VStack(spacing: 18) {
            HStack {
                Text("Badge").font(theme.largeTitle)
                Spacer()
                if env.usingMock {
                    Text("Demo data").font(theme.caption).foregroundStyle(theme.inkSecondary)
                }
            }

            BadgeView(presentation: .window)
                .frame(width: 300, height: 540)
                .clipShape(RoundedRectangle(cornerRadius: theme.badgeCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: theme.badgeCornerRadius).stroke(.white, lineWidth: 6))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
                .scaleEffect(min(max(pinch, 0.95), 1.15))
                .matchedTransitionSource(id: "badge", in: namespace)
                .gesture(
                    MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in if value.magnification > 1.15 { env.badge.wear() } }
                )
                .accessibilityAction(named: "Wear badge") { env.badge.wear() }

            Label("Pinch out to wear it full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.inkSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .fullScreenCover(isPresented: $badge.isWorn) {
            WornBadgeView()
                .navigationTransition(.zoom(sourceID: "badge", in: namespace))
        }
    }
}
