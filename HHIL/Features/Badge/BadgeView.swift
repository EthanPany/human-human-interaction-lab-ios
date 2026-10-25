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
            frontTag: front,
            mode: state.mode,
            closeness: state.closeness,
            matchColor: active ? state.color.map(Color.init(hex:)) : nil,
            peerAvatar: state.peerAvatar,
            peerSeed: AvatarStyle.seed(state.peerId ?? ""),
            look: state.peerId.flatMap { env.nearby.directions[$0] }.map { CGPoint(x: $0, y: 0) },
            followsTilt: state.mode == .idle,
            presentation: presentation,
            orientation: orientation
        )
    }

}
