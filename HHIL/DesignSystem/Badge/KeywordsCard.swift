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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What is on screen. Lags `keywords` while a reshuffle plays out row by row.
    @State private var shown: [String]? = nil
    @State private var reshuffle: Task<Void, Never>?

    /// Each row flips over on its own, one after another, so the reranking reads.
    static let rowDelay: Duration = .milliseconds(420)
    static let flipAnimation = Animation.spring(duration: 0.9, bounce: 0.22)

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            Text(matched ? "Talk to me about" : "Ask me about")
                .font(.brandFixed(17 * scale, .medium))
                .foregroundStyle(theme.ink.opacity(0.7))

            VStack(alignment: .leading, spacing: 6 * scale) {
                // Rows are slots; a slot flips over when its word changes
                ForEach(Array((shown ?? keywords).enumerated()), id: \.offset) { index, keyword in
                    if index > 0 {
                        Rectangle().fill(theme.ink.opacity(0.15)).frame(height: 2 * scale)
                    }
                    // The old and new word share the row while it flips over
                    ZStack(alignment: .leading) {
                        Text(keyword)
                            .font(.brandFixed(fontSize, .semibold))
                            .foregroundStyle(theme.strongInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.55)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(keyword)
                            .transition(.flip)
                    }
                }
            }
        }
        .padding(22 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(matched ? (tint ?? theme.yellow) : theme.yellow, in: shape)
        .animation(.easeInOut(duration: 0.6), value: matched)
        .accessibilityElement(children: .combine)
        .onChange(of: keywords) { old, new in play(from: shown ?? old, to: new) }
        .onDisappear { reshuffle?.cancel() }
    }

    /// Swap the rows one at a time, top to bottom.
    private func play(from old: [String], to new: [String]) {
        reshuffle?.cancel()
        if reduceMotion {
            shown = new
            return
        }
        shown = old
        reshuffle = Task { @MainActor in
            var current = old
            for i in 0..<max(old.count, new.count) {
                if i < new.count {
                    if i < current.count {
                        guard current[i] != new[i] else { continue }
                        current[i] = new[i]
                    } else {
                        current.append(new[i])
                    }
                } else {
                    current.removeLast(current.count - new.count)
                    withAnimation(Self.flipAnimation) { shown = current }
                    break
                }
                withAnimation(Self.flipAnimation) { shown = current }
                try? await Task.sleep(for: Self.rowDelay)
                if Task.isCancelled { return }
            }
            shown = nil // caught up: follow `keywords` directly again
        }
    }
}
