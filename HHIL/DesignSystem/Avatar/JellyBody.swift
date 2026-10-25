import Foundation
import CoreGraphics

/// The avatar's body as a little piece of jelly stuck to the screen.
///
/// When the phone accelerates, the body lags behind (inertia), springs back,
/// overshoots and settles with a few wobbles. It stretches along the way it
/// is moving, squashes when pushed into, and leans as the phone spins. This is
/// pure physics on the raw accelerometer and gyro feed, independent of what
/// activity the wearer is doing.
///
/// On top of that it keeps two feelings: `shock` (a sharp jolt startles it
/// for a moment) and `dizzy` (shaking it for a while makes its eyes spin).
///
/// Plain value type, a handful of doubles, no allocations.
struct JellyBody {
    /// What the renderer and the face read, all in radius units / radians.
    struct Output {
        var offset = CGPoint.zero
        /// Stretch along `stretchAngle` (volume kept, so it thins the other way).
        var stretch = 0.0
        var stretchAngle = 0.0
        /// Extra axis aligned squash (> 0 wide) from being pushed into.
        var squash = 0.0
        var rotation = 0.0
        /// 0...1 startle and dizziness.
        var shock = 0.0
        var dizzy = 0.0
    }

    // Translation spring: about 2 Hz, lightly damped so it overshoots
    private static let omega = 2 * Double.pi * 2.0
    private static let damping = 0.2
    /// Radius units per (g of acceleration * ω²): 0.3 g holds about 0.08.
    private static let gain = 42.0
    // Squash spring: faster and bouncier
    private static let jigOmega = 2 * Double.pi * 3.2
    private static let jigDamping = 0.14
    // Rotation spring
    private static let rotOmega = 2 * Double.pi * 1.6
    private static let rotDamping = 0.22

    private var x = 0.0, y = 0.0, vx = 0.0, vy = 0.0
    private var jig = 0.0, jigV = 0.0
    private var angle = 0.0, angV = 0.0
    private var ax = 0.0, ay = 0.0, az = 0.0, spin = 0.0 // filtered input
    private var shockLevel = 0.0
    private var shakeLoad = 0.0
    private var dizzyLevel = 0.0
    private var handledJolt = -1000.0
    private var primed = false

    private(set) var output = Output()

    /// `strength` scales the motion (Reduce Motion passes a small value) and
    /// `allowDizzy` turns the spinning eyes off when motion should stay calm.
    mutating func step(dt: Double, time t: Double, motion m: MotionSnapshot?, strength: Double, allowDizzy: Bool) {
        guard dt > 0 else { return }
        // Inputs, in screen axes (x right, y down). Stale or missing data is zero.
        var inX = 0.0, inY = 0.0, inZ = 0.0, inSpin = 0.0
        if let m, m.available, t - m.sampleTime < 0.25 {
            inX = Self.deadZone(m.accelX, 0.012)
            inY = -Self.deadZone(m.accelY, 0.012) // device y points up the screen
            inZ = Self.deadZone(m.accelZ, 0.012)
            inSpin = m.rotationZ
            if !primed {
                primed = true
                handledJolt = m.lastJolt
            }
            // A sharp jolt: startled, and a kick to the jelly
            if m.lastJolt > handledJolt {
                handledJolt = m.lastJolt
                if t - m.lastJolt < 0.5 {
                    shockLevel = max(shockLevel, m.joltStrength)
                    jigV += 2.5 * m.joltStrength * strength
                }
            }
        }
        // Light low pass so sensor noise does not fizz the outline
        let f = 1 - exp(-dt * 45)
        ax += (inX - ax) * f
        ay += (inY - ay) * f
        az += (inZ - az) * f
        spin += (inSpin - spin) * f

        // Substeps keep the springs stable on a slow frame
        let steps = max(1, Int(ceil(dt / (1.0 / 120))))
        let h = dt / Double(steps)
        let w2 = Self.omega * Self.omega, c = 2 * Self.damping * Self.omega
        let j2 = Self.jigOmega * Self.jigOmega, jc = 2 * Self.jigDamping * Self.jigOmega
        let r2 = Self.rotOmega * Self.rotOmega, rc = 2 * Self.rotDamping * Self.rotOmega
        let g = Self.gain * strength
        for _ in 0..<steps {
            // The phone accelerates one way, the body is left behind the other way.
            // Stiffens past about 0.15 so a hard swing cannot fling it off the badge.
            let stiff = 1 + 25 * (x * x + y * y)
            vx += (-w2 * stiff * x - c * vx - ax * g) * h
            vy += (-w2 * stiff * y - c * vy - ay * g) * h
            x += vx * h
            y += vy * h
            // Pushed toward the face (phone moving out of the screen) it squashes flat
            jigV += (-j2 * jig - jc * jigV + az * 60 * strength) * h
            jig += jigV * h
            // Body angle relative to the phone: the phone spins, the body tries to stay put
            let rel = angV - spin * 0.5 * strength
            angV += (-r2 * angle - rc * rel) * h
            angle += rel * h
        }

        // Feelings
        shockLevel = max(0, shockLevel - dt / 1.1)
        let shaking = sqrt(ax * ax + ay * ay + az * az)
        shakeLoad += dt * 1.6 * max(0, shaking - 0.5)
        shakeLoad *= exp(-dt * 0.6)
        let target = allowDizzy ? Self.smooth((shakeLoad - 1.0) / 1.2) : 0
        // Gets dizzy quickly, comes round slowly
        dizzyLevel += (target - dizzyLevel) * (1 - exp(-dt * (target > dizzyLevel ? 4 : 0.7)))

        let speed = sqrt(vx * vx + vy * vy)
        var o = Output()
        o.offset = CGPoint(x: 0.22 * tanh(x / 0.22), y: 0.22 * tanh(y / 0.22))
        o.stretch = 0.16 * tanh(speed * 0.65)
        o.stretchAngle = atan2(vy, vx)
        // Hanging low it sits heavy (wide), flung up it stretches tall
        o.squash = max(-0.18, min(0.18, jig + y * 0.6))
        // Screen rotation is clockwise positive; the gyro is counter clockwise positive
        o.rotation = max(-0.35, min(0.35, -angle + Double(o.offset.x) * 0.9))
        o.shock = dizzyLevel > 0.3 ? 0 : Self.smooth(shockLevel)
        o.dizzy = dizzyLevel
        output = o
    }

    private static func deadZone(_ v: Double, _ d: Double) -> Double {
        v > d ? v - d : v < -d ? v + d : 0
    }

    private static func smooth(_ x: Double) -> Double {
        let c = max(0, min(1, x))
        return c * c * (3 - 2 * c)
    }
}
