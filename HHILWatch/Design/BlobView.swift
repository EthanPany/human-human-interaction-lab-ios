import SwiftUI

/// The jelly avatar, simplified for the wrist: the same body shapes as the
/// phone (AvatarShapeKind, shared with the iOS app), breathing and wobbling,
/// with a gloss, round eyes and a blink. No touch, face moods or idle life.
struct BlobView: View {
    var shape: String?
    var color: String?
    /// Stable per person, so two blobs never blink together.
    var seed: Int = 0
    var animated = true
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        let kind = AvatarShapeKind(serverValue: shape)
        let fill = Color(hex: color ?? WatchTheme.defaultAvatar)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated || dimmed)) { context in
            let t = context.date.timeIntervalSinceReferenceDate + Double(seed % 1000) * 0.37
            Canvas { ctx, size in
                Self.draw(kind, fill: fill, time: animated && !dimmed ? t : 0, in: &ctx, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static func draw(_ kind: AvatarShapeKind, fill: Color, time t: Double, in ctx: inout GraphicsContext, size: CGSize) {
        let unit = Double(min(size.width, size.height)) / 2 * 0.92
        let w = Double(size.width), h = Double(size.height)
        let phase = t * 0.9
        let breathe = 1 + 0.02 * sin(t * 2 * Double.pi / 3.2)
        let offset = kind.centerOffset
        let cx = w / 2 + Double(offset.x) * unit
        let cy = h / 2 + Double(offset.y) * unit
        func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
            CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
        }
        var body = Path()
        let steps = 72
        for i in 0...steps {
            let θ = Double(i) / Double(steps) * 2 * Double.pi
            let r = kind.radius(θ, phase: phase) * unit
            // Breathing: a little taller, a little narrower, and back
            let p = CGPoint(x: CGFloat(cx + cos(θ) * r / breathe), y: CGFloat(cy + sin(θ) * r * breathe))
            if i == 0 { body.move(to: p) } else { body.addLine(to: p) }
        }
        body.closeSubpath()
        // Ground shadow, body, gloss
        ctx.fill(Path(ellipseIn: rect(cx - unit * 0.6, cy + unit * 0.88, unit * 1.2, unit * 0.16)),
                 with: .color(fill.opacity(0.25)))
        ctx.fill(body, with: .color(fill))
        ctx.fill(Path(ellipseIn: rect(cx - unit * 0.52, cy - unit * 0.66, unit * 0.42, unit * 0.24)),
                 with: .color(.white.opacity(0.35)))
        // Eyes, blinking about every four seconds
        let eyes = kind.eyes
        let cycle = t.truncatingRemainder(dividingBy: 4.1)
        let blink = cycle > 3.95 ? 0.15 : 1.0
        for e in [eyes.left, eyes.right] {
            let ew = eyes.size * unit * 0.8
            let eh = eyes.size * unit * blink
            let ex = cx + Double(e.x) * unit, ey = cy + Double(e.y) * unit
            ctx.fill(Path(ellipseIn: rect(ex - ew / 2, ey - eh / 2, ew, eh)), with: .color(WatchTheme.avatarInk))
            if blink > 0.5 {
                ctx.fill(Path(ellipseIn: rect(ex - ew * 0.05, ey - eh * 0.3, ew * 0.32, ew * 0.32)),
                         with: .color(.white.opacity(0.9)))
            }
        }
    }
}
