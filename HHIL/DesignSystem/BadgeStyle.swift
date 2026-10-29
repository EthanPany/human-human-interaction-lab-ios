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
    /// The peer is a match. Someone who is not still joins the avatars when
    /// we're together, but the badge shows no tint or glow for them.
    var matched = true
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
    /// Everyone with me in a group (two or more others): all join the stage,
    /// up to `StageMember.shownLimit`, then a "+N" chip. Empty for a pair.
    var groupMembers: [StageMember] = []
    /// Two or more matches in the area: up to two glow on the side edges, one
    /// color per person, stronger as they get closer.
    var edgeGlows: [EdgeGlow] = []
    /// Pretend people (Settings > Demo): the badge says it is a demo.
    var isDemo = false
    /// "Together" comes from Bluetooth alone: the badge says it is an estimate.
    var estimated = false
    /// Where my avatar should look (-1...1) when UWB knows the match's direction.
    var look: CGPoint?
    /// With nobody near, the eyes follow the phone's tilt (read inside the avatar
    /// so tilt updates don't rebuild the whole badge).
    var followsTilt: Bool

    var presentation: Presentation
    var orientation: Orientation

    /// The two avatars share one frame (talking or saved).
    var hasMet: Bool { (together || mode == .talking || mode == .connected) && (peerAvatar != nil || hasGroup) }

    /// Three or more of us together: the group stage.
    var hasGroup: Bool { groupMembers.count >= 2 && (together || mode == .talking) }

    /// 0...1 how strongly the match color tints the badge: grows as they get closer.
    var tintStrength: Double {
        guard pairColors != nil else { return 0 }
        return together ? 1 : max(0, min(1, closeness))
    }

    /// My avatar keeps its own color; proximity tints the badge around it instead.
    var avatarColor: Color { avatar.color }

    /// The two colors the badge blends as a match gets closer: mine and theirs
    /// (or the shared match color when we don't know theirs). Nil when idle.
    var pairColors: (mine: Color, theirs: Color)? {
        if hasGroup {
            // Only matched members tint the badge; the others join without it
            let matchedColors = groupMembers.filter(\.matched).map(\.avatar.color)
            guard let theirs = Color.blend(matchedColors) else { return nil }
            return (avatar.color, theirs)
        }
        guard mode != .idle, matched, let theirs = peerAvatar?.color ?? matchColor else { return nil }
        return (avatar.color, theirs)
    }

    /// The meet ripples: mine and theirs blended; a group blends everyone's colors.
    var rippleColor: Color {
        if hasGroup { return Color.blend([avatar.color] + groupMembers.map(\.avatar.color)) ?? avatar.color }
        return pairColors.map { $0.mine.mix(with: $0.theirs, by: 0.5) } ?? avatarColor
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

/// Someone with me on the badge in a group.
struct StageMember: Equatable, Identifiable {
    /// The stage shows this many others; more become a "+N" chip.
    static let shownLimit = 4

    let id: String
    var avatar: AvatarStyle
    var seed: Int
    /// A match: their color joins the tint.
    var matched: Bool
    /// The meetCount when they arrived: their own jump in and leap play once, then.
    var arrival: Int
}

extension Color {
    /// An even blend of colors (nil for none).
    static func blend(_ colors: [Color]) -> Color? {
        guard var out = colors.first else { return nil }
        for (i, c) in colors.dropFirst().enumerated() {
            out = out.mix(with: c, by: 1 / Double(i + 2))
        }
        return out
    }
}
