import SwiftUI

/// The big topics under the name, readable across a room: 1 to 3 short phrases.
/// With a match near they are what I have that they want to discuss, or what we
/// both want to discuss, and the card takes on the shared match color.
struct KeywordsCard: View {
    var keywords: [String]
    var matched: Bool
    var tint: Color?
    var scale: CGFloat
    var fontSize: CGFloat
    var shape: AnyShape

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            Text(matched ? "Talk to me about" : "Ask me about")
                .font(.brandFixed(17 * scale, .medium))
                .foregroundStyle(theme.ink.opacity(0.7))

            VStack(alignment: .leading, spacing: 6 * scale) {
                ForEach(Array(keywords.enumerated()), id: \.element) { index, keyword in
                    if index > 0 {
                        Rectangle().fill(theme.ink.opacity(0.15)).frame(height: 2 * scale)
                    }
                    Text(keyword)
                        .font(.brandFixed(fontSize, .semibold))
                        .foregroundStyle(theme.strongInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.flip)
                }
            }
            .animation(.spring(duration: 0.55, bounce: 0.25), value: keywords)
        }
        .padding(22 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(matched ? (tint ?? theme.yellow) : theme.yellow, in: shape)
        .animation(.easeInOut(duration: 0.6), value: matched)
        .accessibilityElement(children: .combine)
    }
}
