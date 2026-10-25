import SwiftUI

/// The designer's look: flowing color background, a white identity card with a
/// huge name and a living avatar, and a block of big topics to talk about.
/// Proximity shows up in the avatar (tint and mood), the topics (they switch to
/// what the match wants) and a soft glow of the match color.
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
            let pad = (worn ? 16 : 14) * scale
            // Worn full screen, the cards follow the phone's own corner radius.
            let shape = worn
                ? AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(28 * scale)), isUniform: true))
                : AnyShape(RoundedRectangle(cornerRadius: theme.cornerRadius * scale * 1.6))

            ZStack {
                FlowingBackground()
                MatchGlow(color: c.matchColor, intensity: c.mode == .idle ? 0 : c.closeness)

                if horizontal {
                    HStack(spacing: 14 * scale) {
                        IdentityCard(c: c, scale: scale, nameSize: 92 * scale, shape: shape)
                            .frame(width: geo.size.width * 0.54)
                        keywords(scale: scale, size: 40 * scale, shape: shape)
                    }
                    .padding(pad)
                } else {
                    VStack(spacing: 14 * scale) {
                        IdentityCard(c: c, scale: scale, nameSize: 96 * scale, shape: shape)
                            .frame(height: geo.size.height * 0.54)
                        keywords(scale: scale, size: 42 * scale, shape: shape)
                    }
                    .padding(pad)
                }
            }
        }
    }

    private func keywords(scale: CGFloat, size: CGFloat, shape: AnyShape) -> some View {
        KeywordsCard(
            keywords: c.keywords.isEmpty ? ["Tell your agent what you're into"] : c.keywords,
            matched: c.mode != .idle,
            tint: c.matchColor,
            scale: scale,
            fontSize: c.keywords.isEmpty ? size * 0.6 : size,
            shape: shape
        )
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
