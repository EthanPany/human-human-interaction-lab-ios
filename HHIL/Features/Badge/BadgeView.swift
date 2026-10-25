import SwiftUI

/// Connects live data (profile, moments, badge state, UWB direction) to
/// whatever BadgeStyle the theme uses.
struct BadgeView: View {
    var presentation: BadgeConfiguration.Presentation
    var orientation: BadgeConfiguration.Orientation = .vertical

    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme

    var body: some View {
        theme.badgeStyle.makeBody(configuration)
    }

    private var configuration: BadgeConfiguration {
        let profile = env.session.profile
        let state = env.badge.state
        let active = state.mode != .idle
        let front = active ? state.frontTag : nil
        let tags = profile?.badgeTags ?? []
        var interests = tags
        for hobby in profile?.hobbies ?? [] where !interests.contains(hobby) { interests.append(hobby) }

        return BadgeConfiguration(
            name: profile?.displayName ?? "Your name",
            company: profile?.company?.nilIfBlank,
            role: profile?.headline?.nilIfBlank,
            location: profile?.location?.nilIfBlank,
            layout: profile?.layout ?? .avatar,
            photoURL: profile?.photoURL,
            avatar: profile?.avatar ?? AvatarStyle(shape: nil, color: nil),
            seed: AvatarStyle.seed(profile?.id ?? "me"),
            hasProfile: profile?.isMatchable ?? false,
            interests: BadgeConfiguration.ordered(interests, front: front),
            tags: tags,
            moments: env.session.moments,
            keywords: Self.keywords(active: active, state: state, tags: tags, hobbies: profile?.hobbies ?? []),
            frontTag: front,
            mode: state.mode,
            closeness: Self.closeness(state: state, localMeters: state.peerId.flatMap { env.nearby.diagnostics[$0]?.meters }),
            matchColor: active ? state.color.map(Color.init(hex:)) : nil,
            peerAvatar: state.peerAvatar,
            peerSeed: AvatarStyle.seed(state.peerId ?? ""),
            look: state.peerId.flatMap { env.nearby.directions[$0] }.map { CGPoint(x: $0, y: 0) },
            followsTilt: state.mode == .idle,
            presentation: presentation,
            orientation: orientation
        )
    }

    /// The server decides who the match is; how close they are comes straight
    /// from this phone's UWB reading when it has one (no round trip), on the
    /// same scale as the server: shows from 10 m, full strength at 3 m.
    private static func closeness(state: BadgeState, localMeters: Double?) -> Double {
        guard state.mode == .match, let m = localMeters else { return state.closeness }
        return max(0, min(1, (10 - m) / (10 - 3)))
    }

    /// Match topics from the backend while someone is near, else my own tags
    /// (read locally so profile edits show at once).
    private static func keywords(active: Bool, state: BadgeState, tags: [String], hobbies: [String]) -> [String] {
        if active, let k = state.keywords, !k.isEmpty { return Array(k.prefix(3)) }
        if active, let front = state.frontTag { return [front] }
        return Array((tags.isEmpty ? hobbies : tags).prefix(3))
    }
}
