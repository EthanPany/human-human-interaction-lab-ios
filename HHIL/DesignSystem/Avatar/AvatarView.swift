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
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animated || reduceMotion)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let frame = engine.step(time: t, shape: shape, expression: expression, look: look)
                AvatarRenderer.draw(frame, color: color, in: &context, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(shape.displayName) avatar, \(expression.rawValue)")
    }
}

/// Pure drawing code, separate from timing so it is easy to restyle.
enum AvatarRenderer {
    static let samples = 96

    static func draw(_ f: AvatarEngine.Frame, color: Color, in ctx: inout GraphicsContext, size: CGSize) {
        let unit = min(size.width, size.height) / 2 * 0.86 // leave room to hop and squash
        let hopLift = f.hop * unit * 0.16
        let from = f.morph.from, to = f.morph.to, p = f.morph.progress
        let offset = CGPoint(
            x: lerp(from.centerOffset.x, to.centerOffset.x, p),
            y: lerp(from.centerOffset.y, to.centerOffset.y, p)
        )
        let center = CGPoint(x: size.width / 2 + offset.x * unit,
                             y: size.height / 2 + offset.y * unit - hopLift)

        // Ground shadow shrinks as it hops
        let shadowW = unit * 1.3 * (1 - 0.25 * f.hop)
        ctx.fill(
            Path(ellipseIn: CGRect(x: size.width / 2 - shadowW / 2, y: size.height / 2 + unit * 0.92,
                                   width: shadowW, height: unit * 0.12)),
            with: .color(.black.opacity(0.08 * (1 - 0.5 * f.hop)))
        )

        var layer = ctx
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .radians(f.face.tilt * Double(f.look.x)))
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
        for eye in [left, right] {
            drawEye(at: CGPoint(x: eye.x + drift.x, y: eye.y + drift.y), size: eyeSize, f: f, in: &layer)
        }

        // Blush
        if f.face.blush > 0.01 {
            for eye in [left, right] {
                let r = CGRect(x: eye.x + drift.x - eyeSize * 0.8, y: eye.y + drift.y + eyeSize * 0.9,
                               width: eyeSize * 1.6, height: eyeSize * 0.7)
                layer.fill(Path(ellipseIn: r), with: .color(Color(hex: "#FF6C9A").opacity(0.45 * f.face.blush)))
            }
        }
    }

    /// Closed smooth path through the sampled radii (quad curves through midpoints).
    static func bodyPath(_ f: AvatarEngine.Frame, unit: CGFloat) -> Path {
        let from = f.morph.from, to = f.morph.to, p = f.morph.progress
        var points: [CGPoint] = []
        points.reserveCapacity(samples)
        for i in 0..<samples {
            let θ = Double(i) / Double(samples) * 2 * .pi
            let r = lerp(from.radius(θ, phase: f.phase), to.radius(θ, phase: f.phase), p)
            points.append(CGPoint(x: cos(θ) * r * unit, y: sin(θ) * r * unit))
        }
        var path = Path()
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(points[samples - 1], points[0]))
        for i in 0..<samples {
            let next = points[(i + 1) % samples]
            path.addQuadCurve(to: mid(points[i], next), control: points[i])
        }
        path.closeSubpath()
        return path
    }

    static func drawEye(at c: CGPoint, size e: CGFloat, f: AvatarEngine.Frame, in ctx: inout GraphicsContext) {
        let open = max(0.06, f.face.eyeOpen * f.blink)
        let roundAmount = 1 - f.face.crescent

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
            inside.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2)),
                        with: .color(Color(hex: "#1A1A1A")))
            // Catch light
            inside.fill(Path(ellipseIn: CGRect(x: px - pr * 0.1, y: py - pr * 0.75, width: pr * 0.5, height: pr * 0.5)),
                        with: .color(.white.opacity(0.85)))
            // Sleepy lid line when nearly closed
            if open < 0.5 {
                var lid = Path()
                lid.move(to: CGPoint(x: c.x - w / 2, y: c.y - h / 2))
                lid.addLine(to: CGPoint(x: c.x + w / 2, y: c.y - h / 2))
                eye.stroke(lid, with: .color(Color(hex: "#1A1A1A")), style: StrokeStyle(lineWidth: e * 0.14, lineCap: .round))
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
            eye.stroke(arc, with: .color(Color(hex: "#111111")), style: StrokeStyle(lineWidth: e * 0.38, lineCap: .round))
        }
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
}
