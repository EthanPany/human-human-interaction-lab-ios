import Foundation
import CoreGraphics

/// What the idle life adds to the avatar this frame. Every field is a plain
/// number so two poses can be blended, and `IdlePose()` changes nothing.
struct IdlePose {
    /// Where the eyes want to be (-1...1) and how fast they get there.
    var gaze = CGPoint.zero
    var gazeSpeed = 14.0
    /// How much an outside look target (tilt, peer) still pulls the eyes.
    var outside = 1.0
    /// Multipliers on the expression's eyes.
    var eyeOpen = 1.0
    var eyeScale = 1.0
    /// 0...1 flat, slanted top lids (determined squint).
    var squint = 0.0
    /// Blink frequency multiplier (0 stops new blinks) and blink length multiplier.
    var blinkRate = 1.0
    var blinkLength = 1.0
    /// Body: lift (radius units, up), sway (radians), extra squash, breathing.
    var lift = 0.0
    var sway = 0.0
    var squash = 0.0
    var breatheDepth = 0.0
    var breatheRate = 1.0
    /// Additive toward the happy crescent eyes and the blush.
    var crescent = 0.0
    var blush = 0.0
    /// Drawn extras, 0...1 each.
    var spiral = 0.0
    var mouth = 0.0
    var zzz = 0.0
    var notes = 0.0
    var wind = 0.0
    /// The fly, in radius units from the box center, and how visible it is.
    var fly = CGPoint.zero
    var flyAlpha = 0.0

    /// Blend: face and extras use `face`, body motion uses `body` (0 keeps `a`).
    static func mix(_ a: IdlePose, _ b: IdlePose, face: Double, body: Double) -> IdlePose {
        func m(_ x: Double, _ y: Double, _ k: Double) -> Double { x + (y - x) * k }
        var r = IdlePose()
        r.gaze = CGPoint(x: m(a.gaze.x, b.gaze.x, face), y: m(a.gaze.y, b.gaze.y, face))
        r.gazeSpeed = m(a.gazeSpeed, b.gazeSpeed, face)
        r.outside = m(a.outside, b.outside, face)
        r.eyeOpen = m(a.eyeOpen, b.eyeOpen, face)
        r.eyeScale = m(a.eyeScale, b.eyeScale, face)
        r.squint = m(a.squint, b.squint, face)
        r.blinkRate = m(a.blinkRate, b.blinkRate, face)
        r.blinkLength = m(a.blinkLength, b.blinkLength, face)
        r.lift = m(a.lift, b.lift, body)
        r.sway = m(a.sway, b.sway, body)
        r.squash = m(a.squash, b.squash, body)
        r.breatheDepth = m(a.breatheDepth, b.breatheDepth, body)
        r.breatheRate = m(a.breatheRate, b.breatheRate, body)
        r.crescent = m(a.crescent, b.crescent, face)
        r.blush = m(a.blush, b.blush, face)
        r.spiral = m(a.spiral, b.spiral, face)
        r.mouth = m(a.mouth, b.mouth, face)
        r.zzz = m(a.zzz, b.zzz, face)
        r.notes = m(a.notes, b.notes, face)
        r.wind = m(a.wind, b.wind, face)
        // The fly never slides toward the middle: it keeps whichever position is visible.
        r.fly = b.flyAlpha > 0.001 ? b.fly : a.fly
        r.flyAlpha = m(a.flyAlpha, b.flyAlpha, face)
        return r
    }
}

/// Picks and plays the avatar's idle activities, driven by the engine's clock.
///
/// What the wearer does picks the activity (walking bounces in step, running
/// squints into the wind, a car sways, a shake makes it dizzy, a jolt startles
/// it, long stillness makes it bored and then doze off). When nothing changes
/// it cycles through calm activities with randomized timing, seeded per
/// avatar, so two badges never move in sync and nothing reads as a loop.
/// Activities cross fade, so there are no pops. No allocations per frame.
final class IdleDirector {
    enum Kind: Equatable {
        // Ambient (cycled when nothing happens)
        case calm, stare, fly, reading, bored, hum, doubleTake, doze
        // Events
        case dizzy, startle
        // Activity
        case walk, run, car, hang

        var isActivity: Bool {
            switch self {
            case .walk, .run, .car, .hang, .dizzy, .startle: return true
            default: return false
            }
        }
    }

    private struct Slot {
        var kind: Kind
        var start: Double
        var duration: Double
        var seed: UInt64
        var side: Double // -1 or 1, which way this instance leans
        var a: Double    // 0..<1 per instance variety
        var b: Double
    }

    private var rng: SeededRandom
    private var current: Slot
    private var lastPose = IdlePose()
    private var fadeFrom = IdlePose()
    private var fadeStart = -100.0
    private var fadeLength = 0.9
    private var recent1: Kind = .calm
    private var recent2: Kind = .calm
    private var handledJolt = -1000.0
    private var handledShake = -1000.0
    private var wanted: Kind?
    private var wantedSince = 0.0
    private var started = false

    init(seed: Int) {
        rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed &* 31 &+ 101))
        current = Slot(kind: .calm, start: 0, duration: 8, seed: 1, side: 1, a: 0.5, b: 0.5)
    }

    var kind: Kind { current.kind }

    /// `motion` is nil when this avatar does not feel the phone (lists, editors).
    /// `calm` is the Reduce Motion set: fewer, slower activities, smaller moves.
    func step(time t: Double, motion: MotionSnapshot?, calm: Bool) -> IdlePose {
        if !started {
            started = true
            // Start somewhere different per avatar
            begin(pickAmbient(t: t, stillFor: 0, calm: calm), at: t - rng.next() * 3, fade: 0)
            if let motion {
                handledJolt = motion.lastJolt
                handledShake = motion.lastShake
            }
        }
        choose(t: t, motion: motion, calm: calm)

        let m = motion ?? MotionSnapshot()
        var out = pose(current, t: t, m: m, calm: calm)
        let f = (t - fadeStart) / fadeLength
        if f < 1 {
            // Blend from exactly what was on screen when the switch happened,
            // so even a switch in the middle of another blend cannot pop.
            let k = Self.smooth(max(0, f))
            out = IdlePose.mix(fadeFrom, out, face: k, body: k)
        }
        if calm {
            out.lift *= 0.35
            out.sway *= 0.35
            out.squash *= 0.35
            out.gazeSpeed = min(out.gazeSpeed, 8)
        }
        lastPose = out
        return out
    }

    // MARK: Choosing

    private func choose(t: Double, motion: MotionSnapshot?, calm: Bool) {
        let kind = current.kind
        guard let m = motion, m.available else {
            if t >= current.start + current.duration {
                begin(pickAmbient(t: t, stillFor: 0, calm: calm), at: t, fade: 0.9)
            }
            return
        }
        let moving = m.stepping || m.activity == .walking || m.activity == .running || m.activity == .cycling

        // Events interrupt anything
        if m.lastShake > handledShake {
            handledShake = m.lastShake
            if t - m.lastShake < 1, !moving {
                begin(calm ? .startle : .dizzy, at: t, fade: 0.25)
                return
            }
        }
        if m.lastJolt > handledJolt {
            handledJolt = m.lastJolt
            if t - m.lastJolt < 1, !moving, kind != .dizzy, t - m.lastShake > 1.5 {
                begin(.startle, at: t, fade: 0.2)
                return
            }
        }
        if (kind == .dizzy || kind == .startle) && t < current.start + current.duration { return }

        // Activity, debounced so a single reading does not flicker the face
        let want = activity(m)
        if want != wanted {
            wanted = want
            wantedSince = t
        }
        let stable = t - wantedSince > (want == nil ? 1.5 : 1.0)
        if let want, want != kind, stable {
            begin(want, at: t, fade: 0.8)
            return
        }
        let stillFor = t - m.stillSince
        if want == nil && stable && (kind.isActivity || (kind == .doze && stillFor < 2)) {
            // Woke up or stopped: a stretch and a yawn, then back to the cycle
            begin(kind == .doze ? .bored : pickAmbient(t: t, stillFor: stillFor, calm: calm), at: t, fade: 0.9)
            return
        }
        if kind == .doze { return } // dozes until something happens
        if t >= current.start + current.duration {
            begin(pickAmbient(t: t, stillFor: stillFor, calm: calm), at: t, fade: 0.9)
        }
    }

    private func activity(_ m: MotionSnapshot) -> Kind? {
        if m.faceDown { return .doze }
        if m.upsideDown { return .hang }
        let sure = m.activityConfidence >= 0.5
        switch m.activity {
        case .running where sure, .cycling where sure: return .run
        case .automotive where sure: return .car
        case .walking where sure: return m.stepping && m.stepInterval < 0.36 ? .run : .walk
        default:
            if m.stepping { return m.stepInterval < 0.36 ? .run : .walk }
            return nil
        }
    }

    private func pickAmbient(t: Double, stillFor: Double, calm: Bool) -> Kind {
        // Long stillness: get bored, then doze
        if stillFor > 150 && recent1 == .bored { return .doze }
        let boredBoost = stillFor > 60 ? 3.0 : 1.0
        // Weights, calm set first
        var total = 0.0
        let options: [(Kind, Double)] = calm ? Self.calmWeights : Self.weights
        for (k, w) in options where k != recent1 && k != recent2 {
            total += k == .bored ? w * boredBoost : w
        }
        var r = rng.next() * total
        for (k, w) in options where k != recent1 && k != recent2 {
            r -= k == .bored ? w * boredBoost : w
            if r <= 0 { return k }
        }
        return .calm
    }

    // Static so picking does not allocate
    private static let weights: [(Kind, Double)] = [
        (.calm, 3), (.stare, 1.2), (.fly, 1), (.reading, 1), (.hum, 1), (.doubleTake, 0.8), (.bored, 0.7),
    ]
    private static let calmWeights: [(Kind, Double)] = [
        (.calm, 3), (.stare, 1), (.reading, 1), (.bored, 0.8),
    ]

    private func begin(_ kind: Kind, at t: Double, fade: Double) {
        fadeFrom = lastPose
        fadeStart = t
        fadeLength = max(0.001, fade)
        let r = rng.next()
        let duration: Double
        switch kind {
        case .calm: duration = 6 + r * 9
        case .stare: duration = 5 + r * 3
        case .fly: duration = 6 + r * 5
        case .reading: duration = 6 + r * 5
        case .bored: duration = 6 + r * 3
        case .hum: duration = 5 + r * 4
        case .doubleTake: duration = 3.4
        case .dizzy: duration = 3.5
        case .startle: duration = 1.8
        case .doze, .walk, .run, .car, .hang: duration = .infinity
        }
        current = Slot(kind: kind, start: t, duration: duration,
                       seed: UInt64(truncatingIfNeeded: Int(rng.next() * 1_000_000)) &+ 1,
                       side: rng.next() < 0.5 ? -1 : 1, a: rng.next(), b: rng.next())
        if !kind.isActivity && kind != recent1 {
            recent2 = recent1
            recent1 = kind
        }
    }

    // MARK: Choreography

    private func pose(_ s: Slot, t: Double, m: MotionSnapshot, calm: Bool) -> IdlePose {
        var p = IdlePose()
        let l = max(0, t - s.start) // local time
        // Fade in and out for drawn extras on finite activities
        let edge = s.duration.isFinite ? Self.smooth(min(l, s.duration - l) / 0.6) : Self.smooth(l / 0.6)

        switch s.kind {
        case .calm:
            // Mostly near the middle, sometimes a slow look around
            let seg = 2.4 + s.a * 2
            let i = Int(l / seg)
            let far = Self.hash(s.seed, i * 3) < 0.28
            let reach = far ? 0.75 : 0.25
            p.gaze = CGPoint(x: (Self.hash(s.seed, i * 3 + 1) * 2 - 1) * reach,
                             y: (Self.hash(s.seed, i * 3 + 2) * 2 - 1) * reach * 0.6)
            p.gazeSpeed = far ? 4 : 7
            p.sway = 0.02 * sin(l * 0.7 + s.a * 6)

        case .stare:
            // Looks right at you, barely blinking, then gets shy and looks away
            let shyAt = 2.4 + s.a * 1.6
            if l < shyAt {
                p.gaze = CGPoint(x: 0, y: 0.05)
                p.eyeScale = 1.08
                p.blinkRate = 0.15
                p.outside = 0.2
            } else {
                let u = min(1, (l - shyAt) / 0.5)
                let peek = l > s.duration - 1.2
                p.gaze = peek ? CGPoint(x: s.side * 0.25, y: 0.2) : CGPoint(x: s.side * 0.85, y: 0.55)
                p.gazeSpeed = 10
                p.blush = 0.55 * u
                p.eyeOpen = 0.82
                p.sway = s.side * 0.07 * u
                p.squash = 0.03 * u
                p.outside = 0.2
            }

        case .fly:
            // A fly buzzes around the head, the eyes chase it with a little lag
            let w = 1 + s.a * 0.5
            var x = 0.75 * sin(l * 1.9 * w + s.b * 6) + 0.18 * sin(l * 5.3)
            let y = -0.55 + 0.32 * sin(l * 2.7 * w + s.a * 4) + 0.08 * sin(l * 8.1)
            // Flies in from one side and away to the other
            let arrive = Self.smooth(l / 1.2), leave = Self.smooth((s.duration - l) / 1.2)
            x += s.side * (1 - arrive) * 1.6 - s.side * (1 - leave) * 1.6
            p.fly = CGPoint(x: x, y: y)
            p.flyAlpha = min(arrive, leave)
            p.gaze = CGPoint(x: max(-1, min(1, x / 0.85)), y: max(-1, min(1, (y + 0.1) / 0.8)))
            p.gazeSpeed = 9
            p.outside = 0.1
            p.sway = 0.05 * p.gaze.x
            p.eyeScale = 1.06
            p.blinkRate = 0.5

        case .reading:
            // Reads lines: steps left to right, quick return, next line lower
            let line = 1.6 + s.a * 0.6
            let li = Int(l / line)
            let u = (l / line) - Double(li)
            let sweep = u < 0.85 ? (floor(u / 0.85 * 6) / 5) : (1 - (u - 0.85) / 0.15)
            p.gaze = CGPoint(x: -0.6 + 1.2 * sweep, y: 0.3 + Double(li % 4) * 0.07)
            p.gazeSpeed = 16
            p.squint = 0.22
            p.eyeOpen = 0.9
            p.blinkRate = 0.5
            p.outside = 0.1
            p.sway = 0.03 * sin(l * 0.5) + (li % 4 == 3 ? 0.04 * s.side : 0)

        case .bored:
            // Half lidded, drifting eyes, then a big stretchy yawn
            let yawnAt = 1.4 + s.a * 1.6
            let y = l > yawnAt ? Self.yawn((l - yawnAt) / 2.4) : 0
            p.eyeOpen = 0.55 * (1 - 0.88 * y)
            p.gaze = CGPoint(x: 0.4 * sin(l * 0.35 + s.b * 6), y: 0.25 - 0.4 * y)
            p.gazeSpeed = 3
            p.mouth = y
            p.squash = -0.09 * y
            p.lift = 0.03 * y
            p.sway = 0.03 * sin(l * 0.4)
            p.breatheDepth = 0.012
            p.breatheRate = 0.7
            p.blinkLength = 1.8

        case .doze:
            // Eyes shut, slow deep breaths, zzz, and now and then a droopy check
            let settle = Self.smooth(l / 2.5)
            let checkEvery = 7 + s.a * 4
            let c = l.truncatingRemainder(dividingBy: checkEvery)
            let check = c > checkEvery - 1.3 ? sin((c - (checkEvery - 1.3)) / 1.3 * .pi) : 0
            p.eyeOpen = 1 - settle * (0.93 - 0.3 * check)
            p.blinkRate = 1 - settle
            p.gaze = CGPoint(x: 0.1 * s.side, y: 0.45)
            p.gazeSpeed = 2
            p.zzz = settle
            p.breatheDepth = 0.03 * settle
            p.breatheRate = 0.45
            p.sway = 0.07 * s.side * settle
            p.lift = -0.02 * settle

        case .hum:
            // Bobs to a tune it is humming, happy eyes, notes floating out
            let beat = 2 * .pi * (1.4 + s.a * 0.5)
            p.sway = 0.07 * sin(l * beat * 0.5)
            p.lift = 0.035 * abs(sin(l * beat * 0.5))
            p.squash = 0.02 * pow(1 - abs(sin(l * beat * 0.5)), 4)
            p.crescent = 0.7 * edge
            p.mouth = (0.22 + 0.1 * sin(l * beat)) * edge
            p.notes = edge
            p.gaze = CGPoint(x: 0.25 * sin(l * beat * 0.5), y: -0.2)
            p.gazeSpeed = 8
            p.outside = 0.3

        case .doubleTake:
            // Glance, look back, then snap right back with big eyes
            if l < 0.9 {
                p.gaze = CGPoint(x: s.side * 0.5, y: 0.1)
                p.gazeSpeed = 8
            } else if l < 1.4 {
                p.gaze = CGPoint(x: 0, y: 0)
                p.gazeSpeed = 10
            } else {
                let u = min(1, (l - 1.4) / 0.15)
                p.gaze = CGPoint(x: s.side * 0.95, y: -0.1)
                p.gazeSpeed = 30
                p.eyeScale = 1 + 0.28 * u
                p.eyeOpen = 1.12
                p.lift = 0.05 * u * Self.smooth((2.8 - l) / 0.5)
                p.sway = s.side * 0.08 * u
                p.blinkRate = 0
            }
            p.outside = 0.1

        case .dizzy:
            // Spiral eyes, wobbling body, slowly coming round
            let decay = Self.smooth((s.duration - l) / 1.2)
            p.spiral = Self.smooth(l / 0.25) * decay
            p.sway = 0.1 * sin(l * 5) * decay
            p.squash = 0.04 * sin(l * 7.3) * decay
            p.gaze = CGPoint(x: 0.4 * cos(l * 6), y: 0.3 * sin(l * 6))
            p.gazeSpeed = 20
            p.mouth = 0.15 * decay
            p.blinkRate = 0
            p.outside = 0

        case .startle:
            // Eyes pop, a little jump, a quick look around
            let pop = 1 - Self.smooth(l / 1.4)
            p.eyeScale = 1 + 0.35 * pop
            p.eyeOpen = 1 + 0.25 * pop
            p.lift = 0.14 * sin(.pi * min(1, l / 0.35)) * (l < 0.35 ? 1 : 0)
            p.squash = l < 0.12 ? 0.08 : l < 0.35 ? -0.08 : 0
            p.gaze = l < 0.5 ? CGPoint(x: 0, y: -0.2)
                : l < 0.9 ? CGPoint(x: -s.side * 0.8, y: 0)
                : l < 1.3 ? CGPoint(x: s.side * 0.8, y: 0) : .zero
            p.gazeSpeed = 26
            p.mouth = 0.45 * pop
            p.blinkRate = 0
            p.outside = 0

        case .walk, .run:
            // Body bounces in step with the wearer, eyes on the road ahead
            let running = s.kind == .run
            let interval = m.stepping ? m.stepInterval : (running ? 0.33 : 0.55)
            let phase: Double
            if m.stepping && t - m.lastStep < 1.2 {
                phase = min(1, (t - m.lastStep) / max(0.2, interval))
            } else {
                phase = (l / interval + s.a).truncatingRemainder(dividingBy: 1)
            }
            let up = sin(.pi * phase)
            p.lift = (running ? 0.08 : 0.055) * up
            p.squash = (running ? 0.07 : 0.05) * pow(1 - phase, 5) - 0.02 * up
            p.gaze = CGPoint(x: 0.08 * sin(l * 0.6), y: running ? 0.1 : -0.05)
            p.gazeSpeed = 10
            p.outside = 0.15
            p.sway = (running ? -0.06 : 0) + 0.025 * sin(.pi * phase) * (Int(l / interval) % 2 == 0 ? 1 : -1)
            if running {
                p.squint = 0.75
                p.eyeScale = 0.95
                p.wind = Self.smooth(l / 0.8)
                p.blinkRate = 0.6
            } else {
                p.eyeScale = 1.03
            }

        case .car:
            // Relaxed sway, watching the scenery slide past the window
            p.sway = 0.05 * sin(l * 1.1 + s.a * 6) + 0.02 * sin(l * 2.9)
            p.lift = 0.012 * sin(l * 3.7) + 0.008 * sin(l * 9.1)
            let pass = 1.6 + s.b
            let u = (l / pass).truncatingRemainder(dividingBy: 1)
            p.gaze = CGPoint(x: s.side * (0.7 - 1.2 * u), y: 0.12)
            p.gazeSpeed = u < 0.08 ? 24 : 12
            p.eyeOpen = 0.85
            p.crescent = 0.25
            p.outside = 0.1
            p.breatheDepth = 0.006

        case .hang:
            // Upside down: wide eyes, mouth open, swinging like a pendulum
            p.eyeScale = 1.18
            p.eyeOpen = 1.1
            p.gaze = CGPoint(x: 0.2 * sin(l * 1.3), y: -0.85)
            p.gazeSpeed = 8
            p.sway = 0.09 * sin(l * 2.2)
            p.mouth = 0.3
            p.outside = 0
        }
        return p
    }

    // MARK: Helpers

    static func smooth(_ x: Double) -> Double {
        let c = max(0, min(1, x))
        return c * c * (3 - 2 * c)
    }

    /// 0 -> 1 -> 0 over u in 0...1, held open a moment at the top.
    static func yawn(_ u: Double) -> Double {
        guard u > 0, u < 1 else { return 0 }
        return pow(sin(.pi * u), 0.6)
    }

    /// Stable 0..<1 noise from a seed and an index (splitmix64).
    static func hash(_ seed: UInt64, _ i: Int) -> Double {
        var z = seed &+ UInt64(truncatingIfNeeded: i) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
