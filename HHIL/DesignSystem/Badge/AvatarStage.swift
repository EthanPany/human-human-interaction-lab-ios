import SwiftUI

/// My avatar, and when we meet, theirs: it jumps into my frame along an arc
/// and lands beside mine. The other phone shows the mirror image, so it reads
/// as the two avatars hopping into each other's badge.
struct AvatarStage: View {
    var avatar: AvatarStyle
    var color: Color
    var expression: AvatarExpression
    var look: CGPoint?
    var followsTilt = false
    var seed: Int
    var peer: AvatarStyle?
    var peerSeed: Int
    var hasMet: Bool
    /// Which side the peer comes from (-1 left, 1 right), from UWB direction.
    var peerSide: Double = 1

    @Environment(MotionService.self) private var motion

    // Touch: drag to squish and lean it, tap to make it hop.
    @State private var drag: CGSize = .zero
    @State private var touching = false
    @State private var boops = 0
    @State private var delighted = false

    private var myLook: CGPoint? {
        if touching { return CGPoint(x: drag.width / 60, y: drag.height / 60).clamped }
        if hasMet { return CGPoint(x: peerSide, y: 0) }
        if let look { return look }
        return followsTilt ? CGPoint(x: motion.tiltX, y: motion.tiltY * 0.6) : nil
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                let mySize = hasMet ? size * 0.72 : size
                AvatarView(
                    shape: avatar.shape,
                    color: color,
                    expression: touching ? .excited : delighted ? .happy : expression,
                    look: myLook,
                    seed: seed
                )
                .frame(width: mySize, height: mySize)
                .modifier(Squish(drag: drag, pressed: touching, size: mySize))
                .keyframeAnimator(initialValue: Hop(), trigger: boops) { content, hop in
                    content
                        .scaleEffect(x: 2 - hop.squash, y: hop.squash, anchor: .bottom)
                        .offset(y: hop.lift * mySize)
                } keyframes: { _ in
                    KeyframeTrack(\.lift) {
                        CubicKeyframe(0, duration: 0.07)
                        SpringKeyframe(-0.22, duration: 0.22)
                        SpringKeyframe(0, duration: 0.4, spring: .bouncy)
                    }
                    KeyframeTrack(\.squash) {
                        CubicKeyframe(0.8, duration: 0.07)
                        CubicKeyframe(1.14, duration: 0.18)
                        CubicKeyframe(1, duration: 0.14)
                        CubicKeyframe(0.86, duration: 0.07)
                        SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                    }
                }
                .contentShape(Circle().scale(0.8))
                .gesture(touch(size: mySize))
                .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: boops)
                .sensoryFeedback(.selection, trigger: touching) { _, new in new }
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

extension AvatarStage {
    private func touch(size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !touching { withAnimation(.spring(duration: 0.2)) { touching = true } }
                drag = value.translation
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.32)) { // jelly spring back
                    drag = .zero
                    touching = false
                }
                if moved < 10 { boops += 1 }
                delighted = true
                let mark = boops
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    if boops == mark { withAnimation { delighted = false } }
                }
            }
    }
}

/// Values for the tap hop: lift (fraction of size, negative is up) and squash (1 = rest).
private struct Hop {
    var lift: CGFloat = 0
    var squash: CGFloat = 1
}

/// Follows the finger with a rubber band, leans toward it and stretches along it.
private struct Squish: ViewModifier, Animatable {
    var drag: CGSize
    var pressed: Bool
    var size: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(drag.width, drag.height) }
        set { drag = CGSize(width: newValue.first, height: newValue.second) }
    }

    func body(content: Content) -> some View {
        let reach = max(size, 1) * 0.5
        let band = { (d: CGFloat) in d / (1 + abs(d) / reach) * 0.55 } // rubber band
        let sx = abs(drag.width) / max(size, 1)
        let sy = abs(drag.height) / max(size, 1)
        let press: CGFloat = pressed ? 0.95 : 1
        content
            .scaleEffect(x: (1 + 0.35 * sx - 0.15 * sy) * (2 - press), y: (1 + 0.35 * sy - 0.15 * sx) * press,
                         anchor: .bottom)
            .rotationEffect(.degrees(Double(drag.width / max(size, 1)) * 22), anchor: .bottom)
            .offset(x: band(drag.width), y: band(drag.height))
    }
}

private extension CGPoint {
    var clamped: CGPoint { CGPoint(x: max(-1, min(1, x)), y: max(-1, min(1, y))) }
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
