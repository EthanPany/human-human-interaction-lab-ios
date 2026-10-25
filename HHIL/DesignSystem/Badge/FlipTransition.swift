import SwiftUI

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
