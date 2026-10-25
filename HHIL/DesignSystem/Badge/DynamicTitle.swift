import SwiftUI

/// The line under the name that adapts to who is looking.
///
/// When a match is near it shows the one thing about me they care about most
/// (the front tag). Otherwise it slowly cycles through my role and tags, like a
/// teleprompter. Changes flip in 3D, as the designer's note suggests.
struct DynamicTitle: View {
    var front: String?
    var rotation: [String]
    var font: Font
    var color: Color
    var cycleSeconds: Double = 3.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: cycleSeconds)) { timeline in
            let text = current(at: timeline.date)
            ZStack(alignment: .leading) {
                if let text {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .id(text)
                        .transition(.flip)
                }
            }
            .animation(.spring(duration: 0.55, bounce: 0.25), value: text)
        }
        .accessibilityElement(children: .combine)
    }

    private func current(at date: Date) -> String? {
        if let front { return front }
        guard !rotation.isEmpty else { return nil }
        let index = Int(date.timeIntervalSinceReferenceDate / cycleSeconds) % rotation.count
        return rotation[index]
    }
}

extension AnyTransition {
    /// Rotate in from below, out to the top, around the horizontal axis.
    static var flip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipModifier(angle: -90), identity: FlipModifier(angle: 0)),
            removal: .modifier(active: FlipModifier(angle: 90), identity: FlipModifier(angle: 0))
        )
    }
}

private struct FlipModifier: ViewModifier {
    var angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.6)
            .opacity(abs(angle) > 60 ? 0 : 1)
    }
}
