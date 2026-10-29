import Foundation

/// What the avatar feels. Logic picks one; the engine eases between them.
///
/// Approach borrowed from procedural robot eyes (FluxGarage RoboEyes, Anki
/// Cozmo/Vector, esp32 animated eyes) and state machine avatars (Rive,
/// Duolingo): an emotion is just a set of face parameters, and life comes from
/// idle behaviors layered on top (blinks, saccades, breathing, squash and stretch).
enum AvatarExpression: String, CaseIterable {
    case idle      // nobody special nearby
    case sleepy    // profile empty, or the app is in the background
    case curious   // a match is in range: lean in, look toward them
    case excited   // the match is getting close
    case happy     // talking
    case love      // saved each other
    case held      // being touched: big eyes on the finger, a little blush, no hopping

    var face: FaceParams {
        switch self {
        case .idle: return FaceParams()
        case .sleepy: return FaceParams(eyeOpen: 0.32, eyeScale: 0.95, crescent: 0, bounce: 0.004, bounceSpeed: 0.8, blush: 0)
        case .curious: return FaceParams(eyeOpen: 1, eyeScale: 1.12, crescent: 0, bounce: 0.02, bounceSpeed: 2.2, tilt: 0.09, lookBias: 0.8)
        case .excited: return FaceParams(eyeOpen: 1.05, eyeScale: 1.25, crescent: 0, bounce: 0.07, bounceSpeed: 5.5, tilt: 0.04, lookBias: 1)
        case .happy: return FaceParams(eyeOpen: 1, eyeScale: 1.05, crescent: 1, bounce: 0.04, bounceSpeed: 3.2, blush: 0.35, lookBias: 0.6)
        case .love: return FaceParams(eyeOpen: 1, eyeScale: 1.1, crescent: 1, bounce: 0.05, bounceSpeed: 3.8, blush: 1, lookBias: 0.4)
        case .held: return FaceParams(eyeOpen: 1.08, eyeScale: 1.22, crescent: 0, bounce: 0.004, bounceSpeed: 2, blush: 0.3, tilt: 0.06, lookBias: 1)
        }
    }
}

/// Continuous face parameters. Everything here can be blended.
struct FaceParams {
    /// 0 closed ... 1 open (blinks multiply this)
    var eyeOpen: Double = 1
    var eyeScale: Double = 1
    /// 0 round googly eyes ... 1 happy crescents (the designer's blob eyes)
    var crescent: Double = 0
    /// Hop height in radius units, and hops per second times 2π
    var bounce: Double = 0.012
    var bounceSpeed: Double = 1.4
    var blush: Double = 0
    /// Head tilt in radians toward where it is looking
    var tilt: Double = 0
    /// How strongly the eyes follow the outside look target (vs wandering)
    var lookBias: Double = 0.3

    /// Move `self` toward `target` by `k` (0...1).
    mutating func approach(_ target: FaceParams, _ k: Double) {
        func lerp(_ a: inout Double, _ b: Double) { a += (b - a) * k }
        lerp(&eyeOpen, target.eyeOpen)
        lerp(&eyeScale, target.eyeScale)
        lerp(&crescent, target.crescent)
        lerp(&bounce, target.bounce)
        lerp(&bounceSpeed, target.bounceSpeed)
        lerp(&blush, target.blush)
        lerp(&tilt, target.tilt)
        lerp(&lookBias, target.lookBias)
    }
}
