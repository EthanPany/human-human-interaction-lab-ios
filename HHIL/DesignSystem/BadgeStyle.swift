import SwiftUI

/// Everything a badge design needs to draw itself. Logic decides these values;
/// a BadgeStyle only decides how they look.
struct BadgeConfiguration {
    enum Presentation { case window, worn }
    enum Orientation { case vertical, horizontal }

    // Who
    var name: String
    var company: String?
    var role: String?
    var location: String?
    var layout: BadgeLayout
    var photoURL: URL?
    var avatar: AvatarStyle
    /// Per person seed so two phones' avatars never blink in sync.
    var seed: Int
    var hasProfile: Bool

    /// Badge tags and hobbies in one list, front tag first.
    var interests: [String]
    var tags: [String]
    var moments: [Moment]

    /// The big topics under the name: 1 to 3 phrases of 1 to 5 words.
    /// With a match near, what I have that they want to discuss or what we
    /// both want to; otherwise my own top tags.
    var keywords: [String] = []

    // What is happening
    /// The tag the nearby match cares about most. Nil when nobody is close.
    var frontTag: String?
    var mode: BadgeMode
    /// 0...1 from distance alone (1 = talking distance).
    var closeness: Double
    /// Shared match color (same on both badges), nil when idle.
    var matchColor: Color?
    var peerAvatar: AvatarStyle?
    var peerSeed: Int
    /// We came within talking distance and are still together (before the
    /// server calls it a conversation, too).
    var together = false
    /// Goes up at each "we finally met" moment: the avatars leap to each other.
    var meetCount = 0
    /// Where my avatar should look (-1...1) when UWB knows the match's direction.
    var look: CGPoint?
    /// With nobody near, the eyes follow the phone's tilt (read inside the avatar
    /// so tilt updates don't rebuild the whole badge).
    var followsTilt: Bool

    var presentation: Presentation
    var orientation: Orientation

    /// The two avatars share one frame (talking or saved).
    var hasMet: Bool { (together || mode == .talking || mode == .connected) && peerAvatar != nil }

    /// 0...1 how strongly the match color tints the badge: grows as they get closer.
    var tintStrength: Double {
        guard mode != .idle, matchColor != nil else { return 0 }
        return together ? 1 : max(0, min(1, closeness))
    }

    /// My avatar's color after proximity tinting.
    var avatarColor: Color {
        AvatarTint.color(own: avatar.color, match: matchColor, closeness: mode == .idle ? 0 : closeness)
    }

    var expression: AvatarExpression {
        AvatarTint.expression(mode: mode, closeness: closeness, hasProfile: hasProfile)
    }

    /// Items ordered for display: front item first.
    static func ordered(_ items: [String], front: String?) -> [String] {
        guard let front, items.contains(front) else { return items }
        return [front] + items.filter { $0 != front }
    }
}

/// Swap this to change how the badge looks. Implement makeBody and set it on the Theme.
protocol BadgeStyle {
    @MainActor func makeBody(_ configuration: BadgeConfiguration) -> AnyView
}
