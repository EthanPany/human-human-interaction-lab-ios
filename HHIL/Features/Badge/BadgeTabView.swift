import SwiftUI

/// The Badge tab: your badge as a window. Pinch out (or close an iPhone Duo) to wear it.
struct BadgeTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @Namespace private var namespace
    @GestureState private var pinch: CGFloat = 1
    /// Upward drag on the preview (negative = up); it lifts and grows with the finger.
    @GestureState private var lift: CGFloat = 0

    private static let pinchToWear: CGFloat = 1.15
    /// Approximate display corner radius of current iPhones (points).
    private static let screenCornerRadius: CGFloat = 55
    private static let liftToWear: CGFloat = -70

    var body: some View {
        @Bindable var badge = env.badge
        GeometryReader { geo in
            // A true preview: the same shape as this screen when the badge goes
            // full screen (tall on a phone, wide on an open iPhone Duo or iPad),
            // the same layout, and corners scaled from the screen's own.
            let full = CGSize(
                width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            )
            let aspect = max(0.3, full.width / max(full.height, 1))
            let box = CGSize(width: geo.size.width - 64, height: geo.size.height - 170)
            let width = max(80, min(box.width, box.height * aspect))
            let height = width / aspect
            let scale = width / max(full.width, 1)
            let radius = max(14, Self.screenCornerRadius * scale)
            let orientation: BadgeConfiguration.Orientation = aspect > 1 ? .horizontal : .vertical
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

                BadgeView(presentation: .window, orientation: orientation)
                    .frame(width: width, height: height)
                    // Inner cards round concentrically with this frame
                    .containerShape(RoundedRectangle(cornerRadius: radius))
                    .clipShape(RoundedRectangle(cornerRadius: radius))
                    .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white, lineWidth: 6))
                    .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
                    .scaleEffect(min(max(pinch, 0.95), 1.15) * (1 + min(0.12, -lift / 900)))
                    .offset(y: lift * 0.35)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: lift)
                    .matchedTransitionSource(id: "badge", in: namespace)
                    // Two ways in: pinch out, or swipe up. Swipe down in the
                    // worn badge (or pinch in) takes it off again. One combined
                    // gesture (not simultaneous with the children), so dragging
                    // the avatar squishes it instead of wearing the badge.
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in if value.magnification > Self.pinchToWear { env.badge.wear() } }
                            .simultaneously(with:
                                DragGesture(minimumDistance: 12)
                                    .updating($lift) { value, state, _ in
                                        let dy = value.translation.height
                                        state = dy < 0 ? dy : dy / 6 // resist downward pulls
                                    }
                                    .onEnded { value in
                                        if value.translation.height < Self.liftToWear
                                            || value.predictedEndTranslation.height < -220 {
                                            env.badge.wear()
                                        }
                                    }
                            )
                    )
                    // A tick when letting go would wear it
                    .onChange(of: pinch > Self.pinchToWear || lift < Self.liftToWear) { _, armed in
                        if armed { Feedback.shared.play(.detent) }
                    }
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
        .onAppear { env.badge.isPreviewVisible = true }
        .onDisappear { env.badge.isPreviewVisible = false }
        .fullScreenCover(isPresented: $badge.isWorn) {
            WornBadgeView()
                .navigationTransition(.zoom(sourceID: "badge", in: namespace))
        }
    }

    private var statusLine: String {
        let state = env.badge.state
        let name = state.peerName ?? "Someone"
        switch state.mode {
        case .idle: return "Swipe up or pinch out to wear it. Your badge reacts when someone you should meet comes close."
        case .match: return "\(name) is nearby. Your avatar is taking on your shared color."
        case .talking: return "You're talking with \(name)."
        case .connected: return "\(name) is in your People. Say hi again!"
        }
    }
}
