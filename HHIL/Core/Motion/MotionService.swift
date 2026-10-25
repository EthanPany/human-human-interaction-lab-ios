import CoreMotion
import Foundation
import Observation

/// Device tilt, smoothed, for parallax: the background flows with motion and
/// the avatar's eyes follow the tilt when nobody is nearby.
///
/// It also reads what the wearer is doing, for the avatar's idle life:
/// CMMotionActivityManager (walking, running, in a car...) when the person
/// allows Motion & Fitness, plus cheap signals from device motion that need no
/// permission (jolts, shakes, steps, stillness, face down, upside down).
/// Everything degrades to "unknown" in the simulator or when denied.
@MainActor
@Observable
final class MotionService {
    /// -1...1 left/right tilt and front/back tilt.
    private(set) var tiltX: Double = 0
    private(set) var tiltY: Double = 0
    /// 0...1 how much the phone is moving (walking, swinging on the lanyard).
    private(set) var energy: Double = 0

    /// What the avatar reads every frame. Not observed on purpose: the avatar
    /// polls it from its own 60 fps clock, so updating it never invalidates views.
    @ObservationIgnored private(set) var snapshot = MotionSnapshot()

    private let manager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var activityRunning = false
    // Step detector state (vertical acceleration crossing up through zero)
    @ObservationIgnored private var vertical = 0.0
    @ObservationIgnored private var verticalArmed = false
    // Shake detector: short window of strong, direction changing acceleration
    @ObservationIgnored private var shakeLoad = 0.0
    @ObservationIgnored private var lastAccel = CMAcceleration(x: 0, y: 0, z: 0)
    /// The observed tilt only changes every other sample (30 Hz) and only when
    /// it really moved, so the 60 Hz feed does not re-render the views that read it.
    @ObservationIgnored private var tiltTick = 0
    @ObservationIgnored private var smoothTiltX = 0.0
    @ObservationIgnored private var smoothTiltY = 0.0

    func start() {
        users += 1
        guard users == 1 else { return }
        let now = Date.timeIntervalSinceReferenceDate
        snapshot.stillSince = now
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 60 // the avatar's jelly physics reads raw acceleration
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let self, let motion else { return }
                MainActor.assumeIsolated { self.update(motion) }
            }
        }
        startActivity()
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        if activityRunning {
            activityManager.stopActivityUpdates()
            activityRunning = false
        }
    }

    // MARK: Activity (needs NSMotionUsageDescription and the person's OK)

    private func startActivity() {
        #if targetEnvironment(simulator)
        return
        #else
        // UI tests must never stop on a permission alert.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-uiTest") }) { return }
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        switch CMMotionActivityManager.authorizationStatus() {
        case .denied, .restricted: return
        default: break
        }
        activityRunning = true
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            MainActor.assumeIsolated { self.update(activity) }
        }
        #endif
    }

    private func update(_ a: CMMotionActivity) {
        let kind: MotionSnapshot.Activity
        if a.running { kind = .running }
        else if a.cycling { kind = .cycling }
        else if a.automotive { kind = .automotive }
        else if a.walking { kind = .walking }
        else if a.stationary { kind = .stationary }
        else { kind = .unknown }
        // Low confidence readings only count when they agree with what we had
        if a.confidence == .low && kind != snapshot.activity && snapshot.activity != .unknown { return }
        snapshot.activity = kind
        snapshot.activityConfidence = a.confidence == .high ? 1 : a.confidence == .medium ? 0.66 : 0.33
    }

    // MARK: Device motion

    private func update(_ m: CMDeviceMotion) {
        let now = Date.timeIntervalSinceReferenceDate
        let k = 0.065 // low pass (tuned for 60 Hz, same feel as 0.12 at 30 Hz)
        let x = max(-1, min(1, m.gravity.x * 1.6))
        let y = max(-1, min(1, (m.gravity.y + 0.6) * 1.6)) // upright phone reads about -0.6
        smoothTiltX += (x - smoothTiltX) * k
        smoothTiltY += (y - smoothTiltY) * k
        let a = m.userAcceleration
        let raw = sqrt(a.x * a.x + a.y * a.y + a.z * a.z) // in g
        let magnitude = min(1, raw * 2.5)
        let e = energy + (magnitude - energy) * (magnitude > energy ? 0.16 : 0.02)
        tiltTick &+= 1
        if tiltTick % 2 == 0 {
            if abs(smoothTiltX - tiltX) > 0.002 { tiltX = smoothTiltX }
            if abs(smoothTiltY - tiltY) > 0.002 { tiltY = smoothTiltY }
            if abs(e - energy) > 0.004 { energy = e }
        }

        var s = snapshot
        s.available = true
        s.energy = e
        // Raw feed for the jelly body (device axes, in g and rad/s)
        s.accelX = a.x
        s.accelY = a.y
        s.accelZ = a.z
        s.rotationZ = m.rotationRate.z
        s.sampleTime = now
        s.gravityX = m.gravity.x
        s.gravityY = m.gravity.y
        s.gravityZ = m.gravity.z

        // Stillness: any real movement resets the clock
        if raw > 0.035 { s.stillSince = now }

        // Jolt: one sharp spike (bumped, tapped hard, dropped into a hand)
        if raw > 1.1 && now - s.lastJolt > 0.6 {
            s.lastJolt = now
            s.joltStrength = min(1, (raw - 1.1) / 1.5 + 0.4)
        }

        // Shake: strong acceleration that keeps flipping direction
        let dot = a.x * lastAccel.x + a.y * lastAccel.y + a.z * lastAccel.z
        lastAccel = a
        if raw > 0.9 && dot < 0 { shakeLoad += 1 }
        shakeLoad *= 0.965 // per sample at 60 Hz (0.93 at 30 Hz)
        if shakeLoad > 4.5 {
            s.lastShake = now
            shakeLoad = 0
        }

        // Steps: vertical acceleration (along gravity) rising through a threshold
        let v = -(a.x * m.gravity.x + a.y * m.gravity.y + a.z * m.gravity.z)
        vertical += (v - vertical) * 0.28 // 60 Hz
        if vertical < -0.04 { verticalArmed = true }
        if verticalArmed && vertical > 0.08 {
            verticalArmed = false
            let gap = now - s.lastStep
            if gap > 0.24 && gap < 1.4 {
                s.stepInterval += (gap - s.stepInterval) * 0.3
                s.stepCount = min(s.stepCount + 1, 1000)
            } else if gap >= 1.4 {
                s.stepCount = 0
            }
            if gap > 0.24 { s.lastStep = now }
        }
        if now - s.lastStep > 1.6 { s.stepCount = 0 }
        snapshot = s
    }
}

/// A plain value copy of what the phone is doing. Times are seconds since the
/// reference date, the same clock the avatar's TimelineView uses.
struct MotionSnapshot {
    enum Activity { case unknown, stationary, walking, running, cycling, automotive }

    var available = false
    var activity: Activity = .unknown
    var activityConfidence = 0.0
    var energy = 0.0
    var gravityX = 0.0
    var gravityY = -1.0
    var gravityZ = 0.0
    var stillSince = 0.0
    var lastJolt = -1000.0
    var joltStrength = 0.0
    var lastShake = -1000.0
    var lastStep = -1000.0
    var stepInterval = 0.55
    /// Steps in a row with a steady rhythm (0 when the rhythm breaks).
    var stepCount = 0
    /// Latest user acceleration (g, device axes: x right, y toward the top of
    /// the screen, z out of the screen) and spin around the screen normal (rad/s).
    var accelX = 0.0
    var accelY = 0.0
    var accelZ = 0.0
    var rotationZ = 0.0
    var sampleTime = -1000.0

    /// Screen toward the floor (lying face down, or the badge flipped around).
    var faceDown: Bool { gravityZ > 0.75 }
    /// Phone hanging upside down.
    var upsideDown: Bool { gravityY > 0.65 }
    /// Walking found from steps alone, for when activity is unavailable.
    var stepping: Bool { stepCount >= 4 }
}
