import SwiftUI

/// The designer's soft multicolor background, made alive: a mesh gradient whose
/// points drift like slow water and whose colors slowly bleed into their
/// neighbors. Tilting the phone pushes the flow a little.
struct FlowingBackground: View {
    /// 0 = still, 1 = normal flow. Lower it behind dense content.
    var flow: Double = 1
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MotionService.self) private var motion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: 4,
                height: 4,
                points: points(t),
                colors: colors(t),
                smoothsColors: true
            )
        }
        .overlay(Color.white.opacity(0.14)) // the designer's light wash
        .overlay(GrainOverlay().opacity(0.07).blendMode(.multiply))
        .ignoresSafeArea()
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .accessibilityHidden(true)
    }

    /// Interior points wander on slow, out of phase sine paths; edges slide
    /// along their side so the mesh never tears.
    private func points(_ t: Double) -> [SIMD2<Float>] {
        let speed = 0.06 * flow
        let tiltX = motion.tiltX * 0.08
        let tiltY = motion.tiltY * 0.06
        var out: [SIMD2<Float>] = []
        for row in 0..<4 {
            for col in 0..<4 {
                var x = Double(col) / 3
                var y = Double(row) / 3
                let seed = Double(row * 4 + col)
                let interiorX = col != 0 && col != 3
                let interiorY = row != 0 && row != 3
                if interiorX {
                    x += 0.11 * sin(t * speed * (1 + seed * 0.07) + seed * 1.7) + tiltX
                }
                if interiorY {
                    y += 0.11 * cos(t * speed * (1.1 + seed * 0.05) + seed * 2.3) + tiltY
                }
                out.append(SIMD2(Float(min(1, max(0, x))), Float(min(1, max(0, y)))))
            }
        }
        return out
    }

    /// Each vertex color drifts toward the next one in the palette and back.
    private func colors(_ t: Double) -> [Color] {
        let palette = theme.backgroundPalette
        return palette.indices.map { i in
            let next = palette[(i + 5) % palette.count]
            let amount = 0.5 + 0.5 * sin(t * 0.035 * flow + Double(i) * 0.9)
            return palette[i].mix(with: next, by: amount * 0.6)
        }
    }
}

/// Fine film grain like the designer's texture, drawn once and tiled.
private struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 42)
            let count = Int(size.width * size.height / 14)
            for _ in 0..<count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let a = 0.25 + 0.75 * rng.next()
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black.opacity(a)))
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// Small deterministic random generator (xorshift) for textures and avatars.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    /// 0..<1
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}
