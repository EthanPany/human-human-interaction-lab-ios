import CoreMotion
import Observation

/// Device tilt, smoothed, for parallax: the background flows with motion and
/// the avatar's eyes follow the tilt when nobody is nearby.
/// No permission is needed for device motion.
@MainActor
@Observable
final class MotionService {
    /// -1...1 left/right tilt and front/back tilt.
    private(set) var tiltX: Double = 0
    private(set) var tiltY: Double = 0
    /// 0...1 how much the phone is moving (walking, swinging on the lanyard).
    private(set) var energy: Double = 0

    private let manager = CMMotionManager()
    private var users = 0

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            MainActor.assumeIsolated { self.update(motion) }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }

    private func update(_ m: CMDeviceMotion) {
        let k = 0.12 // low pass
        let x = max(-1, min(1, m.gravity.x * 1.6))
        let y = max(-1, min(1, (m.gravity.y + 0.6) * 1.6)) // upright phone reads about -0.6
        tiltX += (x - tiltX) * k
        tiltY += (y - tiltY) * k
        let a = m.userAcceleration
        let magnitude = min(1, sqrt(a.x * a.x + a.y * a.y + a.z * a.z) * 2.5)
        energy += (magnitude - energy) * (magnitude > energy ? 0.3 : 0.04)
    }
}
