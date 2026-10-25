import SwiftUI

/// The designer's look: flowing color background, white identity card with a
/// huge name and a living avatar, and the yellow interests block. Proximity
/// shows up in the avatar (tint and mood) and a soft glow of the match color.
struct PlayfulBadgeStyle: BadgeStyle {
    func makeBody(_ configuration: BadgeConfiguration) -> AnyView {
        AnyView(PlayfulBadge(c: configuration))
    }
}

private struct PlayfulBadge: View {
    let c: BadgeConfiguration
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let horizontal = c.orientation == .horizontal
            // 1 = the designer's 402 pt portrait frame (or 874 pt landscape)
            let scale = horizontal ? geo.size.width / 874 : geo.size.width / 402
            let worn = c.presentation == .worn
            let pad = (worn ? 22 : 16) * scale

            ZStack {
                FlowingBackground()
                MatchGlow(color: c.matchColor, intensity: c.mode == .idle ? 0 : c.closeness)

                if horizontal {
                    HStack(spacing: 18 * scale) {
                        IdentityCard(c: c, scale: scale, nameSize: 72 * scale)
                            .frame(width: geo.size.width * 0.52)
                        interests(scale: scale, maxMoments: 2)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .padding(pad)
                } else {
                    VStack(spacing: 18 * scale) {
                        IdentityCard(c: c, scale: scale, nameSize: 68 * scale)
                            .frame(height: geo.size.height * (worn ? 0.42 : 0.46))
                        interests(scale: scale, maxMoments: worn ? 3 : 2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, pad)
                    .padding(.top, worn ? geo.safeAreaInsets.top + 24 * scale : pad)
                    .padding(.bottom, pad)
                }
            }
        }
    }

    @ViewBuilder
    private func interests(scale: CGFloat, maxMoments: Int) -> some View {
        if !c.interests.isEmpty || !c.moments.isEmpty {
            InterestsCard(
                interests: c.interests,
                highlighted: c.frontTag,
                moments: c.moments,
                scale: scale,
                maxMoments: maxMoments
            )
        }
    }
}

/// Soft inner glow in the shared match color, stronger as they get closer.
private struct MatchGlow: View {
    var color: Color?
    var intensity: Double

    var body: some View {
        Rectangle()
            .strokeBorder((color ?? .clear).opacity(0.9 * intensity), lineWidth: 10 + 40 * intensity)
            .blur(radius: 18 + 30 * intensity)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.8), value: intensity)
            .ignoresSafeArea()
    }
}
