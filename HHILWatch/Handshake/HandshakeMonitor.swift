import CoreMotion
import Foundation
import Observation

/// Listens to the wrist for a handshake while the phones say someone is
/// within 1 m (WatchStore turns it on and off). Core Motion's device motion
/// gives acceleration without gravity and the gravity direction; projecting
/// one on the other gives "up and down" whatever way the wrist is turned.
@MainActor
@Observable
final class HandshakeMonitor {
    private(set) var isListening = false
    /// Core Motion has no device motion here (the simulator).
    let isAvailable: Bool
    /// Called on the main actor when a handshake ends.
    var onHandshake: (() -> Void)?

    private let manager = CMMotionManager()
    private var detector = HandshakeDetector()
    private var syntheticTask: Task<Void, Never>?

    init() {
        isAvailable = manager.isDeviceMotionAvailable
    }

    func setListening(_ on: Bool) {
        guard on != isListening else { return }
        isListening = on
        if on { start() } else { stop() }
    }

    private func start() {
        detector.reset()
        guard isAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 50
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated { self?.ingest(motion) }
        }
    }

    private func stop() {
        manager.stopDeviceMotionUpdates()
        detector.reset()
    }

    private func ingest(_ m: CMDeviceMotion) {
        let g = m.gravity
        let gLength = max(0.001, (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot())
        let up = (x: -g.x / gLength, y: -g.y / gLength, z: -g.z / gLength)
        let a = m.userAcceleration
        let vertical = a.x * up.x + a.y * up.y + a.z * up.z
        let hx = a.x - vertical * up.x, hy = a.y - vertical * up.y, hz = a.z - vertical * up.z
        let horizontal = (hx * hx + hy * hy + hz * hz).squareRoot()
        if detector.step(time: m.timestamp, vertical: vertical, horizontal: horizontal) {
            onHandshake?()
        }
    }

    /// Simulator and testing: play a made up handshake through the same
    /// detector, in real time, as if the wrist had moved.
    func simulate() {
        syntheticTask?.cancel()
        syntheticTask = Task {
            var local = HandshakeDetector()
            let start = Date().timeIntervalSinceReferenceDate
            for (t, v, h) in HandshakeDetector.syntheticHandshake(start: start) {
                let wait = t - Date().timeIntervalSinceReferenceDate
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                if local.step(time: t, vertical: v, horizontal: h) {
                    onHandshake?()
                    return
                }
            }
        }
    }
}
