import Foundation

/// Every sound and haptic the app makes, by meaning. Views and stores name a
/// cue; `Feedback` decides how it sounds and feels, so the whole app keeps one
/// soft, consistent voice.
enum FeedbackCue {
    // Controls
    case tap
    case buttonPress
    case tabSwitch
    case toggle(on: Bool)
    /// Crossing a gesture threshold ("let go now to wear it").
    case detent

    // Wearing
    case wear
    case takeOff

    // Avatar touch
    case avatarPoke
    /// Tap: the avatar hops (pop on take off).
    case avatarHop
    /// The hop lands.
    case avatarLand
    /// Let go after a drag: a jelly boing, bigger for a bigger stretch (0...1).
    case avatarRelease(stretch: Double)

    // Approach
    case matchAppears
    /// One heartbeat while a match approaches; higher and stronger as closeness (0...1) rises.
    case approachTick(closeness: Double, prominent: Bool)
    case talkStart
    case saved

    case error
}

/// Rendered sounds, one buffer each (approach ticks come in pitch steps).
enum SoundID: Hashable {
    case tap, press, tab, toggleOn, toggleOff, wear, takeOff
    case poke, pop, land, boingSmall, boingBig
    case chime, tick(Int), talk, celebrate, error

    static let tickSteps = 8
}
