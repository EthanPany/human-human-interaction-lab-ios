import SwiftUI

/// Rounded surface for profile blocks and detail sections.
struct Card<Content: View>: View {
    var fill: Color?
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(fill ?? theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }
}

/// Block title, with an optional trailing control (edit pencil, plus).
struct SectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Text(title).font(theme.body).foregroundStyle(theme.ink)
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Small uppercase label.
struct SectionLabel: View {
    var text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(theme.caption.weight(.semibold))
            .foregroundStyle(theme.inkSecondary)
    }
}

/// Cream pill with a small icon, the designer's "Name Tag".
struct TagChip: View {
    var text: String
    var systemImage: String? = "sparkle"
    var size: CGFloat = 16
    var fill: Color?
    var highlighted = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.75, weight: .semibold))
                    .foregroundStyle(theme.red)
            }
            Text(text)
                .font(.brand(size, highlighted ? .semibold : .regular))
                .foregroundStyle(theme.strongInk)
                .lineLimit(1)
        }
        .padding(.horizontal, size * 0.85)
        .padding(.vertical, size * 0.55)
        .background(fill ?? theme.surfaceMuted, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.ink.opacity(highlighted ? 0.9 : 0), lineWidth: 2))
    }
}

/// The designer's square cream icon button with a soft drop shadow.
struct IconButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.strongInk)
                .frame(width: 34, height: 34)
                .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 4)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// Wraps an arbitrary label in the icon button look (for Menu and PhotosPicker).
struct IconButtonLabel: View {
    var systemImage: String
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.strongInk)
            .frame(width: 34, height: 34)
            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 4)
    }
}

/// Main call to action: yellow pill, dark text, same drop shadow.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brand(17, .semibold))
            .foregroundStyle(theme.strongInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            // Shadow on the shape only, close under it (not on the label text)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(theme.yellowStrong)
                    .shadow(color: .black.opacity(0.18), radius: 0, y: 2)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Secondary action: cream pill.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.brand(15, .semibold))
            .foregroundStyle(theme.strongInk)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 1, y: 3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// The red location pill under the name.
struct LocationPill: View {
    var text: String
    var size: CGFloat = 12
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.brand(size, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, size * 1.4)
            .padding(.vertical, size * 0.8)
            .background(theme.red, in: Capsule())
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

/// A text field with its title outside, above the box, and a hint inside.
/// Input text and hint use the theme's dark inks, so they stay readable
/// whatever the system appearance is. Keyboard and autofill settings are set
/// by the caller with the usual modifiers (keyboardType, textContentType, ...).
struct LabeledField: View {
    var title: String
    var hint: String
    @Binding var text: String
    var secure = false
    var footnote: String?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.brand(14, .semibold))
                .foregroundStyle(theme.strongInk)
            Group {
                if secure {
                    SecureField(title, text: $text, prompt: prompt)
                } else {
                    TextField(title, text: $text, prompt: prompt)
                }
            }
            .font(theme.body)
            .foregroundStyle(theme.strongInk)
            .padding(14)
            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))
            if let footnote {
                Text(footnote).font(theme.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    private var prompt: Text {
        Text(hint).foregroundStyle(theme.inkSecondary)
    }
}
