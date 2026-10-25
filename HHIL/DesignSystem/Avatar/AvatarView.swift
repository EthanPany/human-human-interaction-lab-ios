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
        let jelly = f.jelly
        let center = CGPoint(x: size.width / 2 + (offset.x + jelly.offset.x) * unit,
                             y: size.height / 2 + (offset.y + jelly.offset.y) * unit - hopLift)
        let idle = f.idle

        // Ground shadow shrinks as it lifts, and slides a little with the jelly
        let up = max(0, min(1, (lift - jelly.offset.y) / 0.16))
        let shadowW = unit * 1.3 * (1 - 0.25 * up)
        ctx.fill(
            Path(ellipseIn: CGRect(x: size.width / 2 + jelly.offset.x * unit * 0.6 - shadowW / 2,
                                   y: size.height / 2 + unit * 0.92,
                                   width: shadowW, height: unit * 0.12)),
            with: .color(.black.opacity(0.08 * (1 - 0.5 * up)))
        )

        // World space extras around the body (not squashed with it)
        var world = ctx
        world.translateBy(x: center.x, y: center.y)
        if idle.wind > 0.01 { drawWind(idle.wind, time: f.time, unit: unit, in: &world) }

        var layer = ctx
        layer.translateBy(x: center.x, y: center.y)
        // Jelly stretch along the way it is moving (keeps its volume)
        if jelly.stretch > 0.002 {
            let a = jelly.stretchAngle
            layer.rotate(by: .radians(a))
            layer.scaleBy(x: 1 + jelly.stretch, y: 1 / (1 + jelly.stretch))
            layer.rotate(by: .radians(-a))
        }
        layer.rotate(by: .radians(f.face.tilt * Double(f.look.x) + idle.sway + jelly.rotation))
        let squash = f.squash + jelly.squash
        layer.scaleBy(x: f.breathe * (1 + squash), y: f.breathe * (1 - squash))

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
        // A raised brow: one eye a little bigger. A wink closes one into a happy arc.
        let asym = CGFloat(max(-1, min(1, idle.asym))) * 0.18
        drawEye(at: l, size: eyeSize * (1 + asym), inner: 1, wink: max(0, -idle.wink),
                f: f, body: color, in: &layer)
        drawEye(at: r, size: eyeSize * (1 - asym), inner: -1, wink: max(0, idle.wink),
                f: f, body: color, in: &layer)

        // Blush
        if f.face.blush > 0.01 {
            let blush = GraphicsContext.Shading.color(blushPink.opacity(0.45 * f.face.blush))
            for eye in [l, r] {
                let rect = CGRect(x: eye.x - eyeSize * 0.8, y: eye.y + eyeSize * 0.9,
                                  width: eyeSize * 1.6, height: eyeSize * 0.7)
                layer.fill(Path(ellipseIn: rect), with: blush)
            }
        }

        let mc = CGPoint(x: (l.x + r.x) / 2, y: max(l.y, r.y) + eyeSize * 1.05)
        // Smile: a small soft curve, fading out as the mouth opens
        let smile = idle.smile * (1 - min(1, idle.mouth * 3))
        if smile > 0.02 {
            let w = eyeSize * (0.45 + 0.45 * smile)
            var curve = Path()
            curve.move(to: CGPoint(x: mc.x - w / 2, y: mc.y - eyeSize * 0.12))
            curve.addQuadCurve(to: CGPoint(x: mc.x + w / 2, y: mc.y - eyeSize * 0.12),
                               control: CGPoint(x: mc.x, y: mc.y + eyeSize * (0.12 + 0.35 * smile)))
            layer.stroke(curve, with: .color(ink.opacity(min(1, smile * 3))),
                         style: StrokeStyle(lineWidth: eyeSize * 0.15, lineCap: .round))
        }
        // Mouth: a little "o" for humming, gasps and yawns
        if idle.mouth > 0.02 {
            let m = idle.mouth
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

        if idle.puff > 0.01 { drawPuff(idle.puff, age: idle.puffAge, at: mc, eye: eyeSize, in: &layer) }
        if idle.sparkle > 0.01 { drawSparkles(idle.sparkle, side: f.look.x >= 0 ? 1 : -1, time: f.time, unit: unit, in: &world) }
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
    /// `wink` (0...1) closes this eye alone into a happy arc.
    static func drawEye(at c: CGPoint, size e: CGFloat, inner: CGFloat, wink: Double, f: AvatarEngine.Frame,
                        body: Color, in ctx: inout GraphicsContext) {
        let idle = f.idle
        let open = max(0.06, f.face.eyeOpen * f.blink)
        let crescent = max(f.face.crescent, wink)
        let closed = max(0, min(1, idle.closed)) * (1 - crescent)
        let roundAmount = (1 - crescent) * (1 - closed)
        let spiral = idle.spiral

        // Round googly eye: white ball, big black pupil that looks around
        if roundAmount > 0.01 {
            var eye = ctx
            eye.opacity = roundAmount
            let w = e * 1.25, h = e * 1.15 * open
            let ball = Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            eye.fill(ball, with: .color(.white))
            var inside = eye
            inside.clip(to: ball)
            let pr = e * 0.42 * CGFloat(max(0.4, min(1.45, idle.pupil)))
            let px = c.x + f.look.x * e * 0.32
            let py = c.y + f.look.y * e * 0.26
            if spiral < 0.99 {
                var pupil = inside
                pupil.opacity = 1 - spiral
                pupil.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2)),
                           with: .color(ink))
                // Catch light (a second, smaller one on big dreamy pupils)
                pupil.fill(Path(ellipseIn: CGRect(x: px - pr * 0.1, y: py - pr * 0.75, width: pr * 0.5, height: pr * 0.5)),
                           with: .color(.white.opacity(0.85)))
                if idle.pupil > 1.1 {
                    let k = min(1, (idle.pupil - 1.1) * 4)
                    pupil.fill(Path(ellipseIn: CGRect(x: px - pr * 0.55, y: py + pr * 0.2, width: pr * 0.24, height: pr * 0.24)),
                               with: .color(.white.opacity(0.7 * k)))
                }
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
            // Top lid: half lids, sleepy droop, suspicious or sad slants, the
            // determined squint. The edge bows down a little, like a real lid.
            let cover = min(0.95, idle.lidTop + 0.5 * idle.squint)
            if cover > 0.01 {
                let slant = (idle.lidSlant + 0.48 * idle.squint) * min(1, cover * 4)
                let top = c.y - h / 2
                let outerY = top + h * CGFloat(max(0, min(1, cover - 0.25 * slant)))
                let innerY = top + h * CGFloat(max(0, min(1, cover + 0.25 * slant)))
                let outerX = c.x - inner * w * 0.6, innerX = c.x + inner * w * 0.6
                let bow = h * 0.1 * CGFloat(min(1, cover * 3))
                let control = CGPoint(x: c.x, y: (outerY + innerY) / 2 + bow)
                var lid = Path()
                lid.move(to: CGPoint(x: outerX, y: top - e))
                lid.addLine(to: CGPoint(x: innerX, y: top - e))
                lid.addLine(to: CGPoint(x: innerX, y: innerY))
                lid.addQuadCurve(to: CGPoint(x: outerX, y: outerY), control: control)
                lid.closeSubpath()
                inside.fill(lid, with: .color(body))
                var edge = Path()
                edge.move(to: CGPoint(x: outerX, y: outerY))
                edge.addQuadCurve(to: CGPoint(x: innerX, y: innerY), control: control)
                inside.stroke(edge, with: .color(ink.opacity(min(1, cover * 3))), lineWidth: e * 0.12)
            }
            // Bottom lid: rises with a curve up, for smiling and dreamy eyes
            if idle.lidBottom > 0.01 {
                let b = CGFloat(min(0.8, idle.lidBottom))
                let bottom = c.y + h / 2
                let y = bottom - h * b
                var lid = Path()
                lid.move(to: CGPoint(x: c.x - w, y: bottom + e))
                lid.addLine(to: CGPoint(x: c.x + w, y: bottom + e))
                lid.addLine(to: CGPoint(x: c.x + w * 0.6, y: y + h * b * 0.35))
                lid.addQuadCurve(to: CGPoint(x: c.x - w * 0.6, y: y + h * b * 0.35),
                                 control: CGPoint(x: c.x, y: y - h * b * 0.6))
                lid.closeSubpath()
                inside.fill(lid, with: .color(body))
            }
            // Sleepy lid line when nearly closed
            if open < 0.5 {
                var lid = Path()
                lid.move(to: CGPoint(x: c.x - w / 2, y: c.y - h / 2))
                lid.addLine(to: CGPoint(x: c.x + w / 2, y: c.y - h / 2))
                eye.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: e * 0.14, lineCap: .round))
            }
        }

        // Relaxed closed eye, a soft "◡" (content, sighing, asleep)
        if closed > 0.01 {
            var eye = ctx
            eye.opacity = closed
            var arc = Path()
            let r = e * 0.55
            arc.addArc(center: CGPoint(x: c.x, y: c.y - r * 0.4), radius: r,
                       startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            eye.stroke(arc, with: .color(ink), style: StrokeStyle(lineWidth: e * 0.28, lineCap: .round))
        }

        // Happy crescent eye, the designer's "◠" mark (also the winking eye)
        if crescent > 0.01 {
            var eye = ctx
            eye.opacity = crescent
            var arc = Path()
            let r = e * 0.62
            let o = max(open, wink)
            let lift = (1 - o) * e * 0.2
            arc.addArc(center: CGPoint(x: c.x + f.look.x * e * 0.12, y: c.y + r * 0.45 + lift),
                       radius: r * max(0.4, o),
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

    /// A small breath cloud drifting out of the mouth and fading (a sigh).
    static func drawPuff(_ amount: Double, age: Double, at mouth: CGPoint, eye e: CGFloat,
                         in ctx: inout GraphicsContext) {
        let fade = amount * sin(.pi * max(0, min(1, age)))
        guard fade > 0.01 else { return }
        let shade = GraphicsContext.Shading.color(.white.opacity(0.7 * fade))
        for i in 0..<3 {
            let k = CGFloat(i)
            let d = CGFloat(age) * e * (1.6 + k * 0.5)
            let r = e * (0.16 + 0.1 * k) * (0.6 + CGFloat(age))
            let x = mouth.x + e * 0.4 + d, y = mouth.y + e * 0.1 - d * 0.35 + k * e * 0.05
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: shade)
        }
    }

    /// Little four point sparkles twinkling above, on the side it is dreaming toward.
    static func drawSparkles(_ amount: Double, side: CGFloat, time: Double, unit: CGFloat,
                             in ctx: inout GraphicsContext) {
        for i in 0..<3 {
            let k = Double(i)
            let tw = 0.5 + 0.5 * sin(time * (2.2 + k * 0.7) + k * 2.1)
            let s = unit * (0.05 + 0.035 * CGFloat(tw))
            let x = side * unit * (0.45 + 0.28 * CGFloat(k)), y = -unit * (0.95 + 0.18 * CGFloat(i % 2)) + unit * 0.1 * CGFloat(k)
            var star = Path()
            star.move(to: CGPoint(x: x, y: y - s))
            star.addQuadCurve(to: CGPoint(x: x + s, y: y), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x, y: y + s), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x - s, y: y), control: CGPoint(x: x, y: y))
            star.addQuadCurve(to: CGPoint(x: x, y: y - s), control: CGPoint(x: x, y: y))
            ctx.fill(star, with: .color(.white.opacity(0.9 * amount * (0.35 + 0.65 * tw))))
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
