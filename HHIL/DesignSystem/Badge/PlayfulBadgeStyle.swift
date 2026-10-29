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
            // Cards round concentrically with what holds them: the phone's own
            // screen corners when worn, the preview frame's corners in the tab
            // (BadgeTabView sets that as the container shape). So inner radius =
            // outer radius minus the gap, at any size.
            let shape = AnyShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(12 * scale)), isUniform: true))

            ZStack {
                FlowingBackground()
                PairWash(colors: c.pairColors, strength: c.tintStrength)
                MatchGlow(color: c.matchColor, intensity: c.tintStrength)
                EdgeGlows(glows: c.edgeGlows)

                if horizontal {
                    HStack(spacing: 14 * scale) {
                        IdentityCard(c: c, scale: scale, nameSize: 92 * scale, shape: shape, avatarSpace: 100 * scale)
                            .frame(width: geo.size.width * 0.54)
                        keywords(scale: scale, size: 40 * scale, shape: shape)
                    }
                    .padding(pad)
                } else {
                    VStack(spacing: 14 * scale) {
                        IdentityCard(c: c, scale: scale, nameSize: 96 * scale, shape: shape, avatarSpace: 120 * scale)
                            .frame(height: geo.size.height * 0.54)
                        keywords(scale: scale, size: 42 * scale, shape: shape)
                    }
                    .padding(pad)
                }

                if let note = note {
                    // Below the Dynamic Island when worn upright
                    BadgeNotePill(text: note, demo: c.isDemo, scale: scale)
                        .padding(.top, pad + (worn && !horizontal ? 46 * scale : 6 * scale))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: note)
        }
    }

    /// Says plainly when the people on the badge are pretend, or when
    /// "together" is only a Bluetooth estimate.
    private var note: String? {
        if c.isDemo { return "Demo · pretend people" }
        if c.estimated { return "Close by · estimated" }
        return nil
    }

    private func keywords(scale: CGFloat, size: CGFloat, shape: AnyShape) -> some View {
        KeywordsCard(
            keywords: c.keywords.isEmpty ? ["Tell your agent what you're into"] : c.keywords,
            matched: c.mode != .idle && c.matched,
            tint: c.matchColor,
            scale: scale,
            fontSize: c.keywords.isEmpty ? size * 0.6 : size,
            shape: shape
        )
    }
}

/// Both people's avatar colors flowing over the background as one slow
/// current: bands of my color and theirs drift diagonally across the badge and
/// bleed into each other. Faint at the pair's respond range, strong at 1 m.
private struct PairWash: View {
    var colors: (mine: Color, theirs: Color)?
    var strength: Double
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let range = theme.matchWashOpacity
        let opacity = colors != nil && strength > 0 ? range.lowerBound + (range.upperBound - range.lowerBound) * strength : 0
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || opacity == 0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate * theme.pairWashSpeed
            if let colors {
                MeshGradient(width: 3, height: 3, points: Self.points(t), colors: Self.colors(t, colors),
                             smoothsColors: true)
            }
        }
        .opacity(opacity)
        .animation(.easeOut(duration: theme.matchTintResponse), value: opacity)
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// The middle points sway a little so the bands breathe.
    private static func points(_ t: Double) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for row in 0..<3 {
            for col in 0..<3 {
                var x = Double(col) / 2, y = Double(row) / 2
                if col == 1 { x += 0.12 * sin(t * 0.7 + Double(row) * 1.3) }
                if row == 1 { y += 0.12 * cos(t * 0.6 + Double(col) * 1.1) }
                out.append(SIMD2(Float(x), Float(y)))
            }
        }
        return out
    }

    /// One direction for the whole badge: a wave of mine to theirs travelling
    /// from the top left corner to the bottom right.
    private static func colors(_ t: Double, _ c: (mine: Color, theirs: Color)) -> [Color] {
        var out: [Color] = []
        for row in 0..<3 {
            for col in 0..<3 {
                let phase = Double(row + col) * 1.05 - t
                let mix = 0.5 + 0.5 * sin(phase)
                out.append(c.mine.mix(with: c.theirs, by: mix))
            }
        }
        return out
    }
}

/// Soft inner glow in the shared match color, stronger as they get closer.
private struct MatchGlow: View {
    var color: Color?
    var intensity: Double
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .strokeBorder((color ?? .clear).opacity(0.9 * intensity), lineWidth: 10 + 40 * intensity)
            .blur(radius: 18 + 30 * intensity)
            .allowsHitTesting(false)
            .animation(.easeOut(duration: theme.matchTintResponse), value: intensity)
            .ignoresSafeArea()
    }
}

/// Two or more matches in the area at once: a soft glow on each side edge,
/// one person per side in their own color, stronger as they come closer, so
/// the wearer and the people around can tell two of them may show up here.
private struct EdgeGlows: View {
    var glows: [EdgeGlow]
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(glows) { glow in
                    EdgeGlowBand(glow: glow, badgeWidth: geo.size.width)
                        .transition(.move(edge: glow.side == .leading ? .leading : .trailing).combined(with: .opacity))
                }
            }
            .animation(theme.edgeGlowSpring, value: glows.map(\.id))
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct EdgeGlowBand: View {
    var glow: EdgeGlow
    var badgeWidth: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let i = max(0, min(1, glow.intensity))
        let leading = glow.side == .leading
        let width = badgeWidth * (theme.edgeGlowWidth.lowerBound + (theme.edgeGlowWidth.upperBound - theme.edgeGlowWidth.lowerBound) * i)
        let opacity = theme.edgeGlowOpacity.lowerBound + (theme.edgeGlowOpacity.upperBound - theme.edgeGlowOpacity.lowerBound) * i
        let blur = theme.edgeGlowBlur.lowerBound + (theme.edgeGlowBlur.upperBound - theme.edgeGlowBlur.lowerBound) * i
        let color = Color(hex: glow.colorHex)
        LinearGradient(
            colors: [color.opacity(opacity), color.opacity(opacity * 0.4), color.opacity(0)],
            startPoint: leading ? .leading : .trailing,
            endPoint: leading ? .trailing : .leading
        )
        .frame(width: max(1, width))
        .blur(radius: blur)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .leading : .trailing)
        .animation(.easeOut(duration: theme.matchTintResponse), value: i)
    }
}

/// A small pill at the top of the badge ("Demo · pretend people").
private struct BadgeNotePill: View {
    var text: String
    var demo: Bool
    var scale: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.brand(max(11, 15 * scale), .semibold))
            .foregroundStyle(theme.pillText)
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 7 * scale)
            .background(Capsule().fill(demo ? theme.demoPillFill : theme.notePillFill))
            .shadow(color: theme.shadowColor, radius: theme.shadowRadius, y: theme.shadowY)
            .accessibilityAddTraits(.isStaticText)
    }
}
