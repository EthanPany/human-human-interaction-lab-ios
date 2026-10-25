import SwiftUI

/// A living avatar: a colored shape with two eyes that blinks, looks around,
/// breathes and hops, and changes mood with `expression`. Drawn every frame in
/// a Canvas, so shapes morph smoothly and nothing is a static image.
struct AvatarView: View {
    var shape: AvatarShapeKind
    var color: Color
    var expression: AvatarExpression = .idle
    /// Where to look, -1...1 on each axis (peer direction or phone tilt). Nil wanders.
    var look: CGPoint?
    /// Static avatars (lists) draw one frame and stop.
    var animated = true
    var seed: Int = 0

    @State private var engine: AvatarEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.avatarSensesMotion) private var sensesMotion
    @Environment(MotionService.self) private var motion: MotionService?

    init(shape: AvatarShapeKind, color: Color, expression: AvatarExpression = .idle,
         look: CGPoint? = nil, animated: Bool = true, seed: Int = 0) {
        self.shape = shape
        self.color = color
        self.expression = expression
        self.look = look
        self.animated = animated
        self.seed = seed
        _engine = State(initialValue: AvatarEngine(seed: seed, shape: shape))
    }

    var body: some View {
        // Reduce Motion keeps it alive but calmer (fewer activities, smaller moves, 30 fps)
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 30 : 1.0 / 60, paused: !animated)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // `snapshot` is not observed, so reading it here never invalidates the view
                let feel = sensesMotion ? motion?.snapshot : nil
                let frame = engine.step(time: t, shape: shape, expression: expression, look: look,
                                        motion: feel, reduceMotion: reduceMotion)
                AvatarRenderer.draw(frame, color: color, in: &context, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: sensesMotion && animated) {
            guard sensesMotion && animated, let motion else { return }
            motion.start()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            motion.stop()
        }
        .accessibilityElement()
        .accessibilityLabel("\(shape.displayName) avatar, \(expression.rawValue)")
    }
}

extension EnvironmentValues {
    /// The wearer's own badge avatar reacts to how the phone moves (walking,
    /// shaking, lying still). Off for everyone else's avatars.
    @Entry var avatarSensesMotion = false
}

extension View {
    func avatarSensesMotion(_ on: Bool = true) -> some View {
        environment(\.avatarSensesMotion, on)
    }
}

/// Pure drawing code, separate from timing so it is easy to restyle.
enum AvatarRenderer {
    static let samples = 96
    static let ink = Color(hex: "#1A1A1A")
    static let crescentInk = Color(hex: "#111111")
    static let blushPink = Color(hex: "#FF6C9A")
    static let tongue = Color(hex: "#FF8FA8")

    static func draw(_ f: AvatarEngine.Frame, color: Color, in ctx: inout GraphicsContext, size: CGSize) {
        let unit = min(size.width, size.height) / 2 * 0.86 // leave room to hop and squash
        let lift = f.hop * 0.16 + f.idle.lift
        let hopLift = lift * unit
        let from = f.morph.from, to = f.morph.to, p = f.morph.progress
        let offset = CGPoint(
            x: lerp(from.centerOffset.x, to.centerOffset.x, p),
            y: lerp(from.centerOffset.y, to.centerOffset.y, p)
        )
        let center = CGPoint(x: size.width / 2 + offset.x * unit,
                             y: size.height / 2 + offset.y * unit - hopLift)
        let idle = f.idle

        // Ground shadow shrinks as it lifts
        let up = max(0, min(1, lift / 0.16))
        let shadowW = unit * 1.3 * (1 - 0.25 * up)
        ctx.fill(
            Path(ellipseIn: CGRect(x: size.width / 2 - shadowW / 2, y: size.height / 2 + unit * 0.92,
                                   width: shadowW, height: unit * 0.12)),
            with: .color(.black.opacity(0.08 * (1 - 0.5 * up)))
        )

        // World space extras around the body (not squashed with it)
        var world = ctx
        world.translateBy(x: center.x, y: center.y)
        if idle.wind > 0.01 { drawWind(idle.wind, time: f.time, unit: unit, in: &world) }

        var layer = ctx
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .radians(f.face.tilt * Double(f.look.x) + idle.sway))
        layer.scaleBy(x: f.breathe * (1 + f.squash), y: f.breathe * (1 - f.squash))

        // Body
        let body = bodyPath(f, unit: unit)
        layer.fill(body, with: .color(color))
        // Soft top light, kept inside the body
        var lit = layer
        lit.clip(to: body)
        lit.fill(
            Path(ellipseIn: CGRect(x: -unit * 0.9, y: -unit * 1.25, width: unit * 1.5, height: unit * 1.1)),
            with: .color(.white.opacity(0.14))
        )

        // Eyes
        let eyesFrom = from.eyes, eyesTo = to.eyes
        let eyeSize = lerp(eyesFrom.size, eyesTo.size, p) * f.face.eyeScale * unit
        let left = CGPoint(x: lerp(eyesFrom.left.x, eyesTo.left.x, p) * unit,
                           y: lerp(eyesFrom.left.y, eyesTo.left.y, p) * unit)
        let right = CGPoint(x: lerp(eyesFrom.right.x, eyesTo.right.x, p) * unit,
                            y: lerp(eyesFrom.right.y, eyesTo.right.y, p) * unit)
        // Whole face drifts slightly toward the gaze (cheap 3D feel)
        let drift = CGPoint(x: f.look.x * unit * 0.06, y: f.look.y * unit * 0.04)
        let l = CGPoint(x: left.x + drift.x, y: left.y + drift.y)
        let r = CGPoint(x: right.x + drift.x, y: right.y + drift.y)
        drawEye(at: l, size: eyeSize, inner: 1, f: f, body: color, in: &layer)
        drawEye(at: r, size: eyeSize, inner: -1, f: f, body: color, in: &layer)

        // Blush
        if f.face.blush > 0.01 {
            let blush = GraphicsContext.Shading.color(blushPink.opacity(0.45 * f.face.blush))
            for eye in [l, r] {
                let rect = CGRect(x: eye.x - eyeSize * 0.8, y: eye.y + eyeSize * 0.9,
                                  width: eyeSize * 1.6, height: eyeSize * 0.7)
                layer.fill(Path(ellipseIn: rect), with: blush)
            }
        }

        // Mouth: a little "o" for humming, gasps and yawns
        if idle.mouth > 0.02 {
            let m = idle.mouth
            let mc = CGPoint(x: (l.x + r.x) / 2, y: max(l.y, r.y) + eyeSize * 1.05)
            let w = eyeSize * (0.32 + 0.3 * m), h = eyeSize * (0.12 + 0.95 * m)
            let mouth = Path(ellipseIn: CGRect(x: mc.x - w / 2, y: mc.y - h / 2, width: w, height: h))
            layer.fill(mouth, with: .color(ink.opacity(min(1, m * 4))))
            if m > 0.4 {
                var inside = layer
                inside.clip(to: mouth)
                inside.fill(Path(ellipseIn: CGRect(x: mc.x - w * 0.35, y: mc.y + h * 0.1, width: w * 0.7, height: h * 0.6)),
                            with: .color(tongue.opacity((m - 0.4) * 1.6)))
            }
        }

        if idle.zzz > 0.01 { drawZzz(idle.zzz, time: f.time, unit: unit, in: &world) }
        if idle.notes > 0.01 { drawNotes(idle.notes, time: f.time, unit: unit, in: &world) }
        if idle.flyAlpha > 0.01 {
            // The fly lives in the box, not on the body, so it does not hop along
            var box = ctx
            box.translateBy(x: size.width / 2, y: size.height / 2)
            drawFly(at: CGPoint(x: idle.fly.x * unit, y: idle.fly.y * unit), alpha: idle.flyAlpha,
                    time: f.time, unit: unit, in: &box)
        }
    }

    /// Closed smooth path through the sampled radii (quad curves through midpoints).
    /// Points are computed on the fly, so nothing is allocated besides the path.
    static func bodyPath(_ f: AvatarEngine.Frame, unit: CGFloat) -> Path {
        let from = f.morph.from, to = f.morph.to, p = f.morph.progress
        func point(_ i: Int) -> CGPoint {
            let θ = Double(i % samples) / Double(samples) * 2 * .pi
            let r = lerp(from.radius(θ, phase: f.phase), to.radius(θ, phase: f.phase), p)
            return CGPoint(x: cos(θ) * r * unit, y: sin(θ) * r * unit)
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        let first = point(0)
        var current = first
        var path = Path()
        path.move(to: mid(point(samples - 1), first))
        for i in 0..<samples {
            let next = i + 1 == samples ? first : point(i + 1)
            path.addQuadCurve(to: mid(current, next), control: current)
            current = next
        }
        path.closeSubpath()
        return path
    }

    /// `inner` is the direction toward the nose (+1 for the left eye), for slanted lids.
    static func drawEye(at c: CGPoint, size e: CGFloat, inner: CGFloat, f: AvatarEngine.Frame, body: Color,
                        in ctx: inout GraphicsContext) {
        let open = max(0.06, f.face.eyeOpen * f.blink)
        let roundAmount = 1 - f.face.crescent
        let spiral = f.idle.spiral

        // Round googly eye: white ball, big black pupil that looks around
        if roundAmount > 0.01 {
            var eye = ctx
            eye.opacity = roundAmount
            let w = e * 1.25, h = e * 1.15 * open
            let ball = Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            eye.fill(ball, with: .color(.white))
            var inside = eye
            inside.clip(to: ball)
            let pr = e * 0.42
            let px = c.x + f.look.x * e * 0.32
            let py = c.y + f.look.y * e * 0.26
            if spiral < 0.99 {
                var pupil = inside
                pupil.opacity = 1 - spiral
                pupil.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2)),
                           with: .color(ink))
                // Catch light
                pupil.fill(Path(ellipseIn: CGRect(x: px - pr * 0.1, y: py - pr * 0.75, width: pr * 0.5, height: pr * 0.5)),
                           with: .color(.white.opacity(0.85)))
            }
            // Dizzy: a turning spiral instead of the pupil
            if spiral > 0.01 {
                var swirl = inside
                swirl.opacity = spiral
                var path = Path()
                let turns = 2.6, steps = 30
                let spin = f.time * 7 * Double(inner)
                for i in 0...steps {
                    let u = Double(i) / Double(steps)
                    let a = u * turns * 2 * .pi + spin
                    let rad = e * 0.5 * u
                    let pt = CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad * Double(min(1, open * 1.1)))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                swirl.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: e * 0.11, lineCap: .round, lineJoin: .round))
            }
            // Determined squint: flat lids, lower toward the nose
            if f.idle.squint > 0.01 {
                let s = f.idle.squint
                let top = c.y - h / 2
                let outerY = top + h * s * 0.38
                let innerY = top + h * s * 0.62
                let outerX = c.x - inner * w / 2, innerX = c.x + inner * w / 2
                var lid = Path()
                lid.move(to: CGPoint(x: outerX, y: top - e))
                lid.addLine(to: CGPoint(x: innerX, y: top - e))
                lid.addLine(to: CGPoint(x: innerX, y: innerY))
                lid.addLine(to: CGPoint(x: outerX, y: outerY))
                lid.closeSubpath()
                inside.fill(lid, with: .color(body))
                var edge = Path()
                edge.move(to: CGPoint(x: outerX, y: outerY))
                edge.addLine(to: CGPoint(x: innerX, y: innerY))
                inside.stroke(edge, with: .color(ink.opacity(min(1, s * 2))), lineWidth: e * 0.12)
            }
            // Sleepy lid line when nearly closed
            if open < 0.5 {
                var lid = Path()
                lid.move(to: CGPoint(x: c.x - w / 2, y: c.y - h / 2))
                lid.addLine(to: CGPoint(x: c.x + w / 2, y: c.y - h / 2))
                eye.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: e * 0.14, lineCap: .round))
            }
        }

        // Happy crescent eye, the designer's "◠" mark
        if f.face.crescent > 0.01 {
            var eye = ctx
            eye.opacity = f.face.crescent
            var arc = Path()
            let r = e * 0.62
            let lift = (1 - open) * e * 0.2
            arc.addArc(center: CGPoint(x: c.x + f.look.x * e * 0.12, y: c.y + r * 0.45 + lift),
                       radius: r * max(0.4, open),
                       startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            eye.stroke(arc, with: .color(crescentInk), style: StrokeStyle(lineWidth: e * 0.38, lineCap: .round))
        }
    }

    // MARK: Idle extras

    /// Three Z's drifting up and away from the top right of the head.
    static func drawZzz(_ amount: Double, time: Double, unit: CGFloat, in ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let p = (time / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let s = unit * (0.1 + 0.09 * p)
            let x = unit * (0.5 + 0.35 * p) + sin(p * 6 + Double(i)) * unit * 0.04
            let y = -unit * (0.65 + 0.55 * p)
            var z = Path()
            z.move(to: CGPoint(x: x - s / 2, y: y - s / 2))
            z.addLine(to: CGPoint(x: x + s / 2, y: y - s / 2))
            z.addLine(to: CGPoint(x: x - s / 2, y: y + s / 2))
            z.addLine(to: CGPoint(x: x + s / 2, y: y + s / 2))
            ctx.stroke(z, with: .color(ink.opacity(0.6 * amount * sin(.pi * p))),
                       style: StrokeStyle(lineWidth: s * 0.2, lineCap: .round, lineJoin: .round))
        }
    }

    /// Two music notes floating out to either side.
    static func drawNotes(_ amount: Double, time: Double, unit: CGFloat, in ctx: inout GraphicsContext) {
        for i in 0..<2 {
            let side: CGFloat = i == 0 ? 1 : -1
            let p = (time / 1.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
            let x = side * unit * (0.7 + 0.3 * p) + sin(p * 9) * unit * 0.05
            let y = -unit * (0.35 + 0.6 * p)
            let w = unit * 0.11, h = unit * 0.08
            let shade = GraphicsContext.Shading.color(ink.opacity(0.6 * amount * sin(.pi * p)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)), with: shade)
            var stem = Path()
            stem.move(to: CGPoint(x: x + w * 0.42, y: y))
            stem.addLine(to: CGPoint(x: x + w * 0.42, y: y - unit * 0.22))
            stem.addLine(to: CGPoint(x: x + w * 1.1, y: y - unit * 0.16))
            ctx.stroke(stem, with: shade, style: StrokeStyle(lineWidth: unit * 0.025, lineCap: .round, lineJoin: .round))
        }
    }

    /// Streaks rushing past while running.
    static func drawWind(_ amount: Double, time: Double, unit: CGFloat, in ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let speed = 0.55 + Double(i) * 0.12
            let p = (time / speed + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let y = unit * (CGFloat(i) * 0.42 - 0.45)
            let x = unit * (1.25 - 2.5 * p)
            var streak = Path()
            streak.move(to: CGPoint(x: x, y: y))
            streak.addLine(to: CGPoint(x: x + unit * 0.38, y: y))
            ctx.stroke(streak, with: .color(.white.opacity(0.6 * amount * sin(.pi * p))),
                       style: StrokeStyle(lineWidth: unit * 0.035, lineCap: .round))
        }
    }

    /// A tiny fly with buzzing wings.
    static func drawFly(at c: CGPoint, alpha: Double, time: Double, unit: CGFloat, in ctx: inout GraphicsContext) {
        var fly = ctx
        fly.opacity = alpha
        let r = unit * 0.035
        let flap = 0.55 + 0.45 * abs(sin(time * 70))
        let wing = GraphicsContext.Shading.color(.white.opacity(0.85))
        fly.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.9, y: c.y - r * 1.5 * flap, width: r * 1.6, height: r * 1.5 * flap)), with: wing)
        fly.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.3, y: c.y - r * 1.5 * flap, width: r * 1.6, height: r * 1.5 * flap)), with: wing)
        fly.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.8, width: r * 2, height: r * 1.6)), with: .color(ink))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
}
