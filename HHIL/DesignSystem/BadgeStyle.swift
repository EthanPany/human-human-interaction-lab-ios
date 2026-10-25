import SwiftUI

/// Everything a badge design needs to draw itself. Logic decides these values;
/// a BadgeStyle only decides how they look.
struct BadgeConfiguration {
    enum Presentation { case window, worn }
    enum Layout { case vertical, horizontal }

    var name: String
    /// Badge tags with the front tag (if any) first.
    var tags: [String]
    /// The tag the nearby match cares about most. Nil when nobody is close.
    var frontTag: String?
    var mode: BadgeMode
    /// 0...1, stronger as the match gets closer.
    var glow: Double
    /// Shared match color (same on both badges), nil when idle.
    var matchColor: Color?
    var presentation: Presentation
    var layout: Layout

    /// Tags ordered for display: front tag first.
    static func orderedTags(_ tags: [String], front: String?) -> [String] {
        guard let front, tags.contains(front) else { return tags }
        return [front] + tags.filter { $0 != front }
    }
}

/// Swap this to change how the badge looks. Implement makeBody and set it on the Theme.
protocol BadgeStyle {
    @MainActor func makeBody(_ configuration: BadgeConfiguration) -> AnyView
}

/// The current wireframe look: solid match color, big name, tags, a placeholder
/// for the designers' element, and an edge glow for proximity.
struct WireframeBadgeStyle: BadgeStyle {
    func makeBody(_ c: BadgeConfiguration) -> AnyView {
        AnyView(WireframeBadge(c: c))
    }
}

private struct WireframeBadge: View {
    let c: BadgeConfiguration
    @Environment(\.theme) private var theme

    private var worn: Bool { c.presentation == .worn }
    private var nameSize: CGFloat {
        switch (c.layout, worn) {
        case (.horizontal, true): return 112
        case (.vertical, true): return 88
        default: return 56
        }
    }

    var body: some View {
        ZStack {
            (c.matchColor ?? theme.badgeIdle)
                .animation(.easeInOut(duration: 0.6), value: c.matchColor)

            if c.layout == .horizontal {
                HStack(alignment: .center, spacing: 32) {
                    nameAndTags
                    DesignElementPlaceholder(label: "Design element")
                        .frame(width: 200, height: 200)
                }
                .padding(.horizontal, 56)
            } else {
                VStack(alignment: .leading) {
                    HStack {
                        Spacer()
                        DesignElementPlaceholder(label: "Design element")
                            .frame(width: worn ? 200 : 130, height: worn ? 200 : 130)
                    }
                    Spacer()
                    nameAndTags
                }
                .padding(worn ? 30 : 24)
                .padding(.top, worn ? 40 : 0)
                .padding(.bottom, worn ? 40 : 6)
            }

            EdgeGlow(intensity: c.glow)
        }
    }

    private var nameAndTags: some View {
        VStack(alignment: .leading, spacing: worn ? 20 : 14) {
            Text(c.name)
                .font(.system(size: nameSize, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(theme.ink)

            if let front = c.frontTag {
                VStack(alignment: .leading, spacing: 10) {
                    Text(front)
                        .font(.system(size: worn ? 30 : 22, weight: .bold))
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 22))
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    let rest = c.tags.filter { $0 != front }
                    if !rest.isEmpty {
                        Text(rest.joined(separator: " · "))
                            .font(.system(size: worn ? 17 : 14, weight: .semibold))
                            .foregroundStyle(theme.ink.opacity(0.6))
                    }
                }
                .id(front)
            } else {
                FlowLayout(spacing: 10) {
                    ForEach(c.tags, id: \.self) { TagChip(text: $0, size: worn ? 20 : 15) }
                }
            }
        }
        .animation(.spring(duration: 0.5), value: c.frontTag)
    }
}

/// Inner white glow around the edges. 0 = none, 1 = strongest.
struct EdgeGlow: View {
    var intensity: Double

    var body: some View {
        Rectangle()
            .strokeBorder(.white.opacity(0.9 * intensity), lineWidth: 6 + 30 * intensity)
            .blur(radius: 10 + 30 * intensity)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.8), value: intensity)
    }
}
