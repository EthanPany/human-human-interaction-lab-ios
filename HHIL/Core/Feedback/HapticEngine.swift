import CoreHaptics
import UIKit

/// Core Haptics for patterns and the continuous squish, UIKit generators for
/// plain impacts. Devices without a Taptic Engine (and the simulator) skip the
/// Core Haptics part; the UIKit generators are no-ops there.
@MainActor
final class HapticEngine {
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var needsStart = true
    private var squishPlayer: CHHapticAdvancedPatternPlayer?
    private var lastSquishUpdate = 0.0

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)

    enum Impact { case light, soft, rigid }

    func prepare() {
        light.prepare(); soft.prepare(); rigid.prepare()
    }

    func impact(_ kind: Impact, intensity: Double) {
        let i = CGFloat(max(0, min(1, intensity * Feedback.hapticGain)))
        switch kind {
        case .light: light.impactOccurred(intensity: i)
        case .soft: soft.impactOccurred(intensity: i)
        case .rigid: rigid.impactOccurred(intensity: i)
        }
    }

    /// A light tick (the system selection tick has no strength, so the Settings level could not apply).
    func selectionTick() { impact(.light, intensity: 0.4) }
    /// Two firm taps, scaled by the Settings strength like every other cue.
    func failure() { pattern([(0, 0.8, 0.6), (0.12, 0.8, 0.6)]) }

    /// Transient taps: (time s, intensity, sharpness). Falls back to one soft impact.
    func pattern(_ taps: [(Double, Double, Double)]) {
        guard let engine = startedEngine() else {
            if let first = taps.first { impact(.soft, intensity: first.1) }
            return
        }
        let events = taps.map { t, i, s in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(1, i * Feedback.hapticGain))),
                // Round, not clicky: keep sharpness low to match the watery sounds
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(s) * 0.45),
            ], relativeTime: t)
        }
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            needsStart = true
        }
    }

    /// We met: one soft, heavy hit, then a low rumble that dies away like
    /// ripples settling. Falls back to a single soft impact.
    func settle() {
        guard let engine = startedEngine() else {
            impact(.soft, intensity: 1)
            return
        }
        // Every level here is scaled by the Settings strength
        let gain = Float(min(1, Feedback.hapticGain))
        let hit = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: gain),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08),
        ], relativeTime: 0)
        let rumble = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.55 * gain),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.02),
        ], relativeTime: 0.03, duration: 1.1)
        // Decay the rumble from full to nothing, fast at first, then slowly
        let fade = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1),
            CHHapticParameterCurve.ControlPoint(relativeTime: 0.25, value: 0.5),
            CHHapticParameterCurve.ControlPoint(relativeTime: 0.6, value: 0.2),
            CHHapticParameterCurve.ControlPoint(relativeTime: 1.1, value: 0),
        ], relativeTime: 0.03)
        // Two faint after ripples (the fade above scales them down too)
        let ripples = [(0.32, 0.45), (0.6, 0.35)].map { t, i in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(i) * gain),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.05),
            ], relativeTime: t)
        }
        do {
            let pattern = try CHHapticPattern(events: [hit, rumble] + ripples, parameterCurves: [fade])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            needsStart = true
        }
    }

    // MARK: Continuous squish

    func startSquish() {
        guard let engine = startedEngine() else { return }
        let rumble = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
        ], relativeTime: 0, duration: 30)
        do {
            let player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [rumble], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            squishPlayer = player
            setSquish(stretch: 0, force: true)
        } catch {
            needsStart = true
        }
    }

    /// Intensity and sharpness follow the stretch; at most 30 updates a second.
    func setSquish(stretch: Double, force: Bool = false) {
        guard let player = squishPlayer else { return }
        let now = CACurrentMediaTime()
        guard force || now - lastSquishUpdate > 1.0 / 30 else { return }
        lastSquishUpdate = now
        let s = Float(max(0, min(1, stretch)))
        let gain = Float(Feedback.hapticGain)
        try? player.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: min(1, (0.08 + 0.42 * s) * gain), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: -0.35 + 0.3 * s, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    func stopSquish() {
        try? squishPlayer?.stop(atTime: CHHapticTimeImmediate)
        squishPlayer = nil
    }

    // MARK: Engine

    private func startedEngine() -> CHHapticEngine? {
        guard supported else { return nil }
        if engine == nil {
            guard let e = try? CHHapticEngine() else { return nil }
            e.playsHapticsOnly = true
            e.isAutoShutdownEnabled = true
            e.resetHandler = { @Sendable [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.needsStart = true
                    self.squishPlayer = nil
                }
            }
            e.stoppedHandler = { @Sendable [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.needsStart = true
                    self.squishPlayer = nil
                }
            }
            engine = e
        }
        if needsStart {
            do {
                try engine?.start()
                needsStart = false
            } catch {
                return nil
            }
        }
        return engine
    }
}
