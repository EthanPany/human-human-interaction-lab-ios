import SwiftUI

/// My avatar, and when we meet, theirs: it jumps into my frame along an arc
/// and lands beside mine. The other phone shows the mirror image, so it reads
/// as the two avatars hopping into each other's badge. At the "we finally met"
/// moment mine leaps toward theirs too, both land with a squash, and rings
/// spread out from where they land, like a stone dropped into a lake.
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
    /// Goes up at each meet moment: the leap toward each other and the ripples.
    var meetCount = 0
    var rippleColor: Color = .clear

    @Environment(MotionService.self) private var motion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Touch: drag to squish and lean it, tap to make it hop.
    @State private var drag: CGSize = .zero
    /// Where the finger is relative to the avatar, -1...1 (the eyes follow it).
    @State private var finger: CGPoint?
    @State private var touching = false
    @State private var boops = 0
    @State private var delighted = false
    @State private var delightTask: Task<Void, Never>?
    /// Per touch bookkeeping that should not re-render the view.
    @State private var tracker = TouchTracker()

    private static let space = "avatarStage"

    private var myLook: CGPoint? {
        if touching, let finger { return finger }
        if hasMet { return CGPoint(x: peerSide, y: 0) }
        if let look { return look }
        return followsTilt ? CGPoint(x: motion.tiltX, y: motion.tiltY * 0.6) : nil
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let mySize = hasMet ? size * 0.72 : size
            let home = CGPoint(x: geo.size.width / 2 + (hasMet ? -peerSide * size * 0.2 : 0),
                               y: geo.size.height / 2 + (hasMet ? size * 0.12 : 0))
            ZStack {
                MeetRipples(color: rippleColor, trigger: meetCount)
                    .frame(width: size * 1.6, height: size * 0.5)
                    .offset(y: size * 0.4)

                AvatarView(
                    shape: avatar.shape,
                    color: color,
                    expression: touching ? .held : delighted ? .happy : expression,
                    look: myLook,
                    seed: seed
                )
                .frame(width: mySize, height: mySize)
                .modifier(Squish(drag: drag, press: touching ? 1 : 0, size: mySize))
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
                .modifier(MeetLeap(trigger: reduceMotion ? 0 : meetCount, side: peerSide, size: mySize))
                .contentShape(Circle().scale(0.8))
                .gesture(touch(size: mySize, home: home))
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
                    .modifier(MeetLeap(trigger: reduceMotion ? 0 : meetCount, side: -peerSide, size: size * 0.66, delay: 0.12))
                    .offset(x: peerSide * size * 0.28, y: size * 0.14)
                    .transition(.jumpIn(from: peerSide, distance: size * 1.2, height: size * 0.7))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .coordinateSpace(.named(Self.space))
            .animation(.spring(response: 0.7, dampingFraction: 0.62), value: hasMet)
        }
    }
}

extension AvatarStage {
    /// Under this much travel (points) and time a touch is a tap: hop.
    private static let tapSlop: CGFloat = 8
    private static let tapTime = 0.35

    /// Drag and tap in the stage's own space, so moving the avatar doesn't
    /// move the coordinates the gesture is measured in.
    private func touch(size: CGFloat, home: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let t = value.translation
                if !touching {
                    tracker.begin(at: value.time)
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) { touching = true }
                    Feedback.shared.play(.avatarPoke)
                }
                tracker.travel = max(tracker.travel, hypot(t.width, t.height))
                if !tracker.dragging, tracker.travel > Self.tapSlop {
                    tracker.dragging = true
                    Feedback.shared.beginSquish()
                }
                drag = t
                // Eyes on the finger: from where the body is now (it lags behind on the rubber band)
                let body = Squish.bodyOffset(drag: t, size: size)
                let reach = max(size * 0.35, 1)
                finger = CGPoint(x: (value.location.x - home.x - body.width) / reach,
                                 y: (value.location.y - home.y - body.height) / reach).clamped
                if tracker.dragging { Feedback.shared.squish(stretch: Squish.stretch(drag: t, size: size)) }
            }
            .onEnded { value in
                let held = value.time.timeIntervalSince(tracker.start)
                let isTap = !tracker.dragging && held < Self.tapTime
                let stretch = Squish.stretch(drag: value.translation, size: size)
                if tracker.dragging { Feedback.shared.endSquish() }
                tracker.dragging = false

                // Jelly spring back: wobblier the further it was pulled
                let spring: Animation = isTap
                    ? .spring(response: 0.28, dampingFraction: 0.7)
                    : .spring(response: 0.5, dampingFraction: 0.42 - 0.14 * stretch)
                withAnimation(spring) {
                    drag = .zero
                    touching = false
                    finger = nil
                }
                if isTap {
                    boops += 1
                    Feedback.shared.play(.avatarHop)
                    let mark = boops
                    Task {
                        try? await Task.sleep(for: .seconds(0.5)) // the hop lands
                        if boops == mark { Feedback.shared.play(.avatarLand) }
                    }
                } else {
                    Feedback.shared.play(.avatarRelease(stretch: stretch))
                }
                delighted = true
                delightTask?.cancel()
                delightTask = Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    guard !Task.isCancelled else { return }
                    withAnimation { delighted = false }
                }
            }
    }
}

/// Touch bookkeeping kept out of SwiftUI state so it doesn't redraw.
private final class TouchTracker {
    var start = Date()
    var travel: CGFloat = 0
    var dragging = false

    func begin(at time: Date) {
        start = time
        travel = 0
        dragging = false
    }
}

/// The meet leap: crouch, jump toward the other avatar along an arc, land with
/// a heavy squash (when the settling sound hits) and wobble back to rest.
private struct MeetLeap: ViewModifier {
    var trigger: Int
    /// Which way to leap (-1 left, 1 right).
    var side: Double
    var size: CGFloat
    var delay: Double = 0

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: Leap(), trigger: trigger) { content, leap in
            content
                .scaleEffect(x: 2 - leap.squash, y: leap.squash, anchor: .bottom)
                .offset(x: CGFloat(side) * leap.travel * size, y: leap.lift * size)
        } keyframes: { _ in
            KeyframeTrack(\.lift) {
                CubicKeyframe(0, duration: 0.1 + delay)
                CubicKeyframe(-0.3, duration: 0.22)
                CubicKeyframe(0, duration: 0.2)
                SpringKeyframe(0, duration: 0.5, spring: .bouncy)
            }
            KeyframeTrack(\.travel) {
                CubicKeyframe(0, duration: 0.1 + delay)
                CubicKeyframe(0.16, duration: 0.42)
                SpringKeyframe(0, duration: 0.8, spring: .smooth)
            }
            KeyframeTrack(\.squash) {
                CubicKeyframe(0.8, duration: 0.1 + delay)
                CubicKeyframe(1.12, duration: 0.2)
                CubicKeyframe(1, duration: 0.22)
                CubicKeyframe(0.74, duration: 0.07)
                SpringKeyframe(1, duration: 0.6, spring: .bouncy)
            }
        }
    }
}

private struct Leap {
    var lift: CGFloat = 0
    /// Toward the other avatar, as a fraction of size.
    var travel: CGFloat = 0
    var squash: CGFloat = 1
}

/// Rings spreading out over water from where the avatars land, then gone.
private struct MeetRipples: View {
    var color: Color
    var trigger: Int

    var body: some View {
        Color.clear
            .keyframeAnimator(initialValue: Ripple(), trigger: trigger) { _, ripple in
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        let p = max(0, min(1, ripple.progress * 1.35 - Double(i) * 0.18))
                        Ellipse()
                            .stroke(color, lineWidth: 2 + 5 * (1 - p))
                            .scaleEffect(0.25 + 0.9 * p)
                            .opacity(ripple.opacity * (1 - p) * (p > 0 ? 1 : 0))
                    }
                }
            } keyframes: { _ in
                KeyframeTrack(\.progress) {
                    LinearKeyframe(0, duration: 0.6)
                    CubicKeyframe(1, duration: 1.7)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.6)
                    LinearKeyframe(0.8, duration: 0.05)
                    CubicKeyframe(0, duration: 1.65)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct Ripple {
    var progress: Double = 0
    var opacity: Double = 0
}

/// Values for the tap hop: lift (fraction of size, negative is up) and squash (1 = rest).
private struct Hop {
    var lift: CGFloat = 0
    var squash: CGFloat = 1
}

/// Follows the finger with a rubber band, leans toward it and stretches along
/// it. Everything saturates, so a long pull never turns into a giant smear.
private struct Squish: ViewModifier, Animatable {
    var drag: CGSize
    /// 0 released ... 1 pressed (squashed down a little), animated with the drag.
    var press: CGFloat
    var size: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(drag.width, drag.height), press) }
        set {
            drag = CGSize(width: newValue.first.first, height: newValue.first.second)
            press = newValue.second
        }
    }

    /// Rubber band: follows 1:2 near the start, flattening out further away.
    static func band(_ d: CGFloat, size: CGFloat) -> CGFloat {
        let reach = max(size, 1) * 0.5
        return d / (1 + abs(d) / reach) * 0.55
    }

    static func bodyOffset(drag: CGSize, size: CGFloat) -> CGSize {
        CGSize(width: band(drag.width, size: size), height: band(drag.height, size: size))
    }

    /// 0...1 how stretched it looks (drives the squish sound and haptics).
    static func stretch(drag: CGSize, size: CGFloat) -> Double {
        let d = hypot(drag.width, drag.height)
        return Double(d / (d + max(size, 1) * 0.5))
    }

    func body(content: Content) -> some View {
        let unit = max(size, 1)
        let soft = { (d: CGFloat) in d / (1 + abs(d)) } // -1...1
        let sx = soft(abs(drag.width) / unit * 1.2)
        let sy = soft(abs(drag.height) / unit * 1.2)
        let squash = 0.06 * press
        let offset = Self.bodyOffset(drag: drag, size: size)
        content
            .scaleEffect(x: (1 + 0.32 * sx - 0.12 * sy) * (1 + squash),
                         y: (1 + 0.32 * sy - 0.12 * sx) * (1 - squash),
                         anchor: .bottom)
            .rotationEffect(.degrees(Double(soft(drag.width / unit * 1.4)) * 18), anchor: .bottom)
            .offset(x: offset.width, y: offset.height)
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
