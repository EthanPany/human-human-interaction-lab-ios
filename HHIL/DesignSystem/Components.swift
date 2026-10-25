import SwiftUI

/// Rounded surface for profile blocks and detail sections.
struct Card<Content: View>: View {
    var fill: Color?
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(fill ?? theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }
}

/// Small uppercase label above a block.
struct SectionLabel: View {
    var text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(theme.caption)
            .foregroundStyle(theme.inkSecondary)
    }
}

/// A tag pill.
struct TagChip: View {
    var text: String
    var size: CGFloat = 15
    var fill: Color = .white.opacity(0.85)
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(fill, in: Capsule())
    }
}

/// Dashed box marking where the designers' element (puzzle piece, blob) goes.
struct DesignElementPlaceholder: View {
    var label: String
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .strokeBorder(theme.placeholderStroke, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .overlay(
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(8)
            )
    }
}

/// Wraps children onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
