import Foundation
import UIKit

/// The one place that plays cues: `Feedback.shared.play(.buttonPress)`.
/// Sounds and haptics each have their own switch in Settings (stored with
/// @AppStorage under the keys below). Reduce Motion only affects visuals.
@MainActor
final class Feedback {
    static let shared = Feedback()

    static let soundsKey = "feedback.sounds"
    static let hapticsKey = "feedback.haptics"
    /// Settings sliders, 0...1. Default all the way up: events are loud.
    static let soundLevelKey = "feedback.soundLevel"
    static let hapticLevelKey = "feedback.hapticLevel"

    /// Sound level: 0 is quiet (40% of the old mix), 1 is the loudest the cues go.
    static var soundLevel: Double { UserDefaults.standard.double(forKey: soundLevelKey) }
    /// Haptic strength multiplier: 0.5x at 0, 1.6x at 1 (capped at full strength).
    static var hapticGain: Double { 0.5 + 1.1 * UserDefaults.standard.double(forKey: hapticLevelKey) }

    private lazy var sound = SoundEngine()
    private let haptics = HapticEngine()
    private var lastPlayed: [String: Double] = [:]

    // Squish tracking (for motion = how fast the stretch changes)
    private var squishing = false
    private var lastStretch = 0.0
    private var lastStretchTime = 0.0
    private var motion = 0.0
    private var lastDetent = 0

    private init() {
        UserDefaults.standard.register(defaults: [Self.soundsKey: true, Self.hapticsKey: true,
                                                  Self.soundLevelKey: 1.0, Self.hapticLevelKey: 1.0])
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Feedback.shared.suspend() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Feedback.shared.prepare() }
        }
    }

    var soundsOn: Bool { UserDefaults.standard.bool(forKey: Self.soundsKey) }
    var hapticsOn: Bool { UserDefaults.standard.bool(forKey: Self.hapticsKey) }

    /// Warm up the haptic generators (and render the sounds) before the first touch.
    func prepare() {
        if hapticsOn { haptics.prepare() }
        if soundsOn { sound.warmUp() }
    }

    func play(_ cue: FeedbackCue) {
        let s = soundsOn, h = hapticsOn
        guard s || h else { return }
        switch cue {
        case .tap:
            guard throttle("tap", 0.05) else { return }
            if s { sound.play(.tap, volume: 0.8) }
            if h { haptics.impact(.light, intensity: 0.5) }
        case .buttonPress:
            guard throttle("press", 0.06) else { return }
            if s { sound.play(.press, volume: 0.8) }
            if h { haptics.impact(.soft, intensity: 0.7) }
        case .tabSwitch:
            guard throttle("tab", 0.08) else { return }
            if s { sound.play(.tab, volume: 0.7) }
            if h { haptics.selectionTick() }
        case .toggle(let on):
            if s { sound.play(on ? .toggleOn : .toggleOff) }
            if h { haptics.impact(.rigid, intensity: on ? 0.6 : 0.4) }
        case .detent:
            guard throttle("detent", 0.15) else { return }
            if s { sound.play(.tap, volume: 0.6) }
            if h { haptics.selectionTick() }
        case .wear:
            if s { sound.play(.wear) }
            if h { haptics.pattern([(0, 0.5, 0.3), (0.12, 0.8, 0.5)]) }
        case .takeOff:
            if s { sound.play(.takeOff) }
            if h { haptics.pattern([(0, 0.7, 0.4), (0.1, 0.4, 0.2)]) }
        case .avatarPoke:
            guard throttle("poke", 0.08) else { return }
            if s { sound.play(.poke, volume: 0.8) }
            if h { haptics.impact(.soft, intensity: 0.55) }
        case .avatarHop:
            if s { sound.play(.pop) }
            if h { haptics.pattern([(0, 0.6, 0.6)]) }
        case .avatarLand:
            guard throttle("land", 0.15) else { return }
            if s { sound.play(.land, volume: 0.7) }
            if h { haptics.impact(.soft, intensity: 0.45) }
        case .avatarRelease(let stretch):
            let x = max(0, min(1, stretch))
            if s { sound.play(x > 0.4 ? .boingBig : .boingSmall, volume: Float(0.35 + 0.65 * x)) }
            if h {
                // A bounce that decays like the jelly spring
                let i = 0.35 + 0.6 * x
                haptics.pattern([(0, i, 0.5), (0.16, i * 0.55, 0.35), (0.31, i * 0.28, 0.25)])
            }
        case .matchAppears:
            guard throttle("match", 3) else { return }
            if s { sound.play(.chime) }
            if h { haptics.pattern([(0, 0.55, 0.5), (0.11, 0.85, 0.7)]) }
        case .approachTick(let closeness, let prominent):
            let c = max(0, min(1, closeness))
            let step = Int((c * Double(SoundID.tickSteps - 1)).rounded())
            if s { sound.play(.tick(step), volume: Float((prominent ? 0.55 : 0.35) + 0.35 * c)) }
            if h {
                let i = 0.3 + 0.65 * c, sharp = 0.15 + 0.5 * c
                haptics.pattern([(0, i, sharp), (0.13, i * 0.6, sharp * 0.7)])
            }
        case .met:
            guard throttle("met", 3) else { return }
            if s { sound.play(.met) }
            if h { haptics.settle() }
        case .talkStart:
            guard throttle("talk", 2) else { return }
            if s { sound.play(.talk) }
            if h { haptics.pattern([(0, 0.6, 0.3), (0.1, 0.8, 0.45)]) }
        case .saved:
            guard throttle("saved", 2) else { return }
            if s { sound.play(.celebrate) }
            if h {
                haptics.pattern([(0, 0.5, 0.5), (0.075, 0.6, 0.55), (0.15, 0.7, 0.6), (0.225, 1, 0.75)])
            }
        case .error:
            if s { sound.play(.error) }
            if h { haptics.failure() }
        }
    }

    // MARK: Continuous squish

    func beginSquish() {
        guard !squishing else { return }
        squishing = true
        lastStretch = 0
        lastStretchTime = CACurrentMediaTime()
        motion = 0
        lastDetent = 0
        if soundsOn { sound.startSquish() }
        if hapticsOn { haptics.startSquish() }
    }

    /// Call on every drag change with the stretch (0...1).
    func squish(stretch: Double) {
        guard squishing else { return }
        let now = CACurrentMediaTime()
        let dt = max(1.0 / 240, now - lastStretchTime)
        let speed = min(1, abs(stretch - lastStretch) / dt / 2.5) // 0...1
        motion += (speed - motion) * (speed > motion ? 0.6 : 0.2)
        lastStretch = stretch
        lastStretchTime = now
        if soundsOn { sound.squish.set(stretch: stretch, motion: motion) }
        if hapticsOn {
            haptics.setSquish(stretch: stretch)
            // Little rubbery detents every so often as it stretches further
            let detent = Int(stretch / 0.18)
            if detent > lastDetent { haptics.pattern([(0, 0.25 + 0.4 * stretch, 0.6)]) }
            lastDetent = detent
        }
    }

    func endSquish() {
        guard squishing else { return }
        squishing = false
        sound.stopSquish()
        haptics.stopSquish()
    }

    private func suspend() {
        endSquish()
        sound.suspend()
    }

    /// False when the same cue played less than `interval` seconds ago.
    private func throttle(_ key: String, _ interval: Double) -> Bool {
        let now = CACurrentMediaTime()
        if let last = lastPlayed[key], now - last < interval { return false }
        lastPlayed[key] = now
        return true
    }
}
