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
    /// Where my avatar should look (-1...1) when UWB knows the match's direction.
    var look: CGPoint?
    /// With nobody near, the eyes follow the phone's tilt (read inside the avatar
    /// so tilt updates don't rebuild the whole badge).
    var followsTilt: Bool

    var presentation: Presentation
    var orientation: Orientation

    /// The two avatars share one frame (talking or saved).
    var hasMet: Bool { (mode == .talking || mode == .connected) && peerAvatar != nil }

    /// My avatar's color after proximity tinting.
    var avatarColor: Color {
        AvatarTint.color(own: avatar.color, match: matchColor, closeness: mode == .idle ? 0 : closeness)
    }

    var expression: AvatarExpression {
        AvatarTint.expression(mode: mode, closeness: closeness, hasProfile: hasProfile)
    }

    /// Lines the dynamic title cycles through when nobody is near.
    var titleRotation: [String] {
        var lines: [String] = []
        if let role { lines.append(role) }
        lines += tags.filter { $0 != role }
        return lines
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
