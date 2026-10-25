import SwiftUI

/// My avatar, and when we meet, theirs: it jumps into my frame along an arc
/// and lands beside mine. The other phone shows the mirror image, so it reads
/// as the two avatars hopping into each other's badge.
struct AvatarStage: View {
    var avatar: AvatarStyle
    var color: Color
    var expression: AvatarExpression
    var look: CGPoint?
    var seed: Int
    var peer: AvatarStyle?
    var peerSeed: Int
    var hasMet: Bool
    /// Which side the peer comes from (-1 left, 1 right), from UWB direction.
    var peerSide: Double = 1

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                AvatarView(
                    shape: avatar.shape,
                    color: color,
                    expression: expression,
                    look: hasMet ? CGPoint(x: peerSide, y: 0) : look,
                    seed: seed
                )
                .frame(width: hasMet ? size * 0.72 : size, height: hasMet ? size * 0.72 : size)
                .offset(x: hasMet ? -peerSide * size * 0.2 : 0, y: hasMet ? size * 0.12 : 0)

                if hasMet, let peer {
                    AvatarView(
                        shape: peer.shape,
                        color: peer.color,
                        expression: expression,
                        look: CGPoint(x: -peerSide, y: 0),
                        seed: peerSeed
                    )
                    .frame(width: size * 0.66, height: size * 0.66)
                    .offset(x: peerSide * size * 0.28, y: size * 0.14)
                    .transition(.jumpIn(from: peerSide, distance: size * 1.2, height: size * 0.7))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.7, dampingFraction: 0.62), value: hasMet)
        }
    }
}

extension AnyTransition {
    /// Enter along a parabola from off to one side, with a spin, like a hop.
    static func jumpIn(from side: Double, distance: CGFloat, height: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: JumpEffect(progress: 0, side: side, distance: distance, height: height),
                identity: JumpEffect(progress: 1, side: side, distance: distance, height: height)
            ),
            removal: .opacity.combined(with: .scale(scale: 0.6))
        )
    }
}

/// progress 0 = off screen to the side, 1 = landed.
struct JumpEffect: GeometryEffect {
    var progress: Double
    var side: Double
    var distance: CGFloat
    var height: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let p = max(0, min(1.2, progress))
        let x = CGFloat(side) * distance * CGFloat(1 - p)
        let y = -height * CGFloat(sin(min(1, p) * .pi)) // up, then down
        let spin = CGFloat(side) * CGFloat(1 - min(1, p)) * .pi * 0.5
        var t = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
        t = t.translatedBy(x: x, y: y)
        t = t.rotated(by: spin)
        t = t.translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(t)
    }
}
