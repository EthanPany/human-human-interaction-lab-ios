import Foundation
import CoreGraphics

/// Per avatar animation state, advanced once per frame by AvatarView.
///
/// Layers, bottom to top:
///   1. Shape morph: when the shape changes, radii blend from old to new.
///   2. Expression: face parameters ease toward the target expression.
///   3. Idle life: breathing, jelly wobble, hops with squash and stretch,
///      random blinks and eye saccades.
///   4. Attention: eyes and head tilt follow an outside look target.
///   5. Idle activities (IdleDirector): what it is doing when nobody is near,
///      picked from what the wearer is doing. Full strength in the idle
///      expression, a light touch of the body motion in the others.
///   6. Jelly body (JellyBody): lags behind, jiggles and leans with the
///      phone's own acceleration and spin, in every expression. A jolt
///      startles the face and long shaking makes it dizzy (idle face only).
final class AvatarEngine {
    struct Frame {
        var phase: Double
        var morph: (from: AvatarShapeKind, to: AvatarShapeKind, progress: Double)
        var face: FaceParams
        var blink: Double      // 1 open ... 0 closed
        var look: CGPoint      // -1...1
        var hop: Double        // 0...1 height
        var squash: Double     // >0 squashed (wide), <0 stretched (tall)
        var breathe: Double    // scale around 1
        var time: Double       // seconds, for drawn extras
        var idle: IdlePose     // already weighted by how idle the face is
        var jelly: JellyBody.Output
    }

    private var rng: SeededRandom
    private var lastTime: Double?
    private var face = FaceParams()
    private var lookNow = CGPoint.zero
    private var wanderTarget = CGPoint.zero
    private var nextSaccade = 0.0
    private var nextBlink = 0.0
    private var blinkStart: Double?
    private var doubleBlink = false
    private var shapeFrom: AvatarShapeKind
    private var shapeTo: AvatarShapeKind
    private var morphStart = -100.0
    private var hopPhase = 0.0
    private var breathePhase = 0.0
    private let director: IdleDirector
    private var idleWeight = 1.0
    private var jelly = JellyBody()

    init(seed: Int, shape: AvatarShapeKind) {
        rng = SeededRandom(seed: UInt64(truncatingIfNeeded: seed &+ 7))
        shapeFrom = shape
        shapeTo = shape
        director = IdleDirector(seed: seed)
    }

    func step(time t: Double, shape: AvatarShapeKind, expression: AvatarExpression, look target: CGPoint?,
              motion: MotionSnapshot? = nil, reduceMotion: Bool = false) -> Frame {
        let dt = min(0.1, max(0, t - (lastTime ?? t)))
        lastTime = t

        // 5. Idle activity, blended in by how idle the expression is
        idleWeight += ((expression == .idle ? 1 : 0) - idleWeight) * (1 - exp(-dt * 3))
        let raw = director.step(time: t, motion: motion, calm: reduceMotion)
        let bodyWeight = idleWeight + (1 - idleWeight) * (director.kind.isActivity ? 0.35 : 0)
        var idle = IdlePose.mix(IdlePose(), raw, face: idleWeight, body: bodyWeight)

        // 6. Jelly body from the phone's motion, and the faces it causes
        jelly.step(dt: dt, time: t, motion: motion, strength: reduceMotion ? 0.35 : 1, allowDizzy: !reduceMotion)
        let jo = jelly.output
        let shock = jo.shock * idleWeight
        if shock > 0.001 {
            // Startled: eyes pop open with tiny pupils, an "o" mouth, lids fly up
            let calmer = 1 - shock
            idle.lidTop *= calmer
            idle.lidBottom *= calmer
            idle.squint *= calmer
            idle.closed *= calmer
            idle.wink *= calmer
            idle.crescent *= calmer
            idle.eyeScale += (1.32 - idle.eyeScale) * shock
            idle.eyeOpen += (1.2 - idle.eyeOpen) * shock
            idle.pupil += (0.5 - idle.pupil) * shock
            idle.mouth = max(idle.mouth, 0.5 * shock)
            idle.blinkRate *= calmer
            idle.gaze = CGPoint(x: Double(idle.gaze.x) * calmer,
                                y: Double(idle.gaze.y) + (-0.15 - Double(idle.gaze.y)) * shock)
            idle.gazeSpeed = max(idle.gazeSpeed, 28)
            idle.outside *= calmer
        }
        let dizzy = jo.dizzy * idleWeight
        if dizzy > 0.001 {
            // Spinning eyes, a wobbly sway and a wavy little mouth
            let calmer = 1 - dizzy
            idle.spiral = max(idle.spiral, dizzy)
            idle.lidTop = idle.lidTop * calmer + 0.15 * dizzy
            idle.closed *= calmer
            idle.crescent *= calmer
            idle.wink *= calmer
            idle.sway += 0.1 * sin(t * 5) * dizzy
            idle.squash += 0.04 * sin(t * 7.3) * dizzy
            idle.mouth = max(idle.mouth, 0.15 * dizzy)
            idle.blinkRate *= calmer
            idle.outside *= calmer
            idle.gaze = CGPoint(x: Double(idle.gaze.x) * calmer + 0.4 * cos(t * 6) * dizzy,
                                y: Double(idle.gaze.y) * calmer + 0.3 * sin(t * 6) * dizzy)
            idle.gazeSpeed = max(idle.gazeSpeed, 20)
        }

        // 1. Shape morph
        if shape != shapeTo {
            // Interrupted mid morph: start from whichever shape we were closer to.
            let progress = (t - morphStart) / 0.7
            shapeFrom = progress < 0.5 ? shapeFrom : shapeTo
            shapeTo = shape
            morphStart = t
        }
        let morphRaw = min(1, (t - morphStart) / 0.7)
        let morph = Self.easeOutBack(morphRaw)

        // 2. Expression easing (about 250 ms)
        face.approach(expression.face, 1 - exp(-dt * 8))

        // 3a. Blinks every 2 to 6 s, sometimes double
        if blinkStart == nil && t >= nextBlink {
            if idle.blinkRate < 0.05 {
                nextBlink = t + 0.3 // hold the stare
            } else {
                blinkStart = t
                doubleBlink = rng.next() < idle.blinkDouble
            }
        }
        var blink = 1.0
        if let start = blinkStart {
            let length = (doubleBlink ? 0.42 : 0.16) * idle.blinkLength
            let p = (t - start) / length
            if p >= 1 {
                blinkStart = nil
                nextBlink = t + (2 + rng.next() * 4) / max(0.05, idle.blinkRate)
            } else {
                let local = doubleBlink ? (p * 2).truncatingRemainder(dividingBy: 1) : p
                blink = abs(cos(local * .pi)) // 1 -> 0 -> 1
            }
        }

        // 3b. Saccades: jump to a new random gaze point every 0.8 to 3 s
        if t >= nextSaccade {
            wanderTarget = CGPoint(x: rng.next() * 1.6 - 0.8, y: rng.next() * 1.0 - 0.5)
            nextSaccade = t + 0.8 + rng.next() * 2.2
        }

        // 4. Attention blends wander with the outside target
        // The idle activity steers the gaze; the outside target can still pull
        let wander = CGPoint(x: wanderTarget.x + (idle.gaze.x - wanderTarget.x) * idleWeight,
                             y: wanderTarget.y + (idle.gaze.y - wanderTarget.y) * idleWeight)
        let bias = target == nil ? 0 : face.lookBias * idle.outside
        let goal = CGPoint(
            x: wander.x * (1 - bias) + (target?.x ?? 0) * bias,
            y: wander.y * (1 - bias) + (target?.y ?? 0) * bias
        )
        let k = 1 - exp(-dt * idle.gazeSpeed) // eyes move fast unless the activity says otherwise
        lookNow.x += (goal.x - lookNow.x) * k
        lookNow.y += (goal.y - lookNow.y) * k

        // 3c. Hops: |sin| arc, squash on landing, stretch on take off
        hopPhase += dt * face.bounceSpeed
        let s = sin(hopPhase)
        let bounce = face.bounce * (reduceMotion ? 0.3 : 1)
        let hop = abs(s) * bounce / 0.07 // normalized for the drawer
        let landing = pow(1 - abs(s), 6)
        let squash = bounce * (2.2 * landing - 0.8 * abs(cos(hopPhase)) * (1 - landing)) + idle.squash
        breathePhase += dt * 1.7 * idle.breatheRate

        // Idle eye shape on top of the expression
        var shown = face
        shown.eyeOpen *= idle.eyeOpen
        shown.eyeScale *= idle.eyeScale
        shown.crescent = min(1, shown.crescent + idle.crescent * (1 - shown.crescent))
        shown.blush = min(1, shown.blush + idle.blush)

        return Frame(
            phase: t * 0.9,
            morph: (shapeFrom, shapeTo, morph),
            face: shown,
            blink: blink,
            look: lookNow,
            hop: min(1, hop),
            squash: squash,
            breathe: 1 + (0.018 + idle.breatheDepth) * sin(breathePhase),
            time: t,
            idle: idle,
            jelly: jo
        )
    }

    /// Overshoots a little before settling: reads as squishy.
    static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}
