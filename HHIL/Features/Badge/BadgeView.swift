import SwiftUI

/// Connects live data (profile + badge state) to whatever BadgeStyle the theme uses.
struct BadgeView: View {
    var presentation: BadgeConfiguration.Presentation
    var layout: BadgeConfiguration.Layout = .vertical

    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme

    var body: some View {
        theme.badgeStyle.makeBody(configuration)
    }

    private var configuration: BadgeConfiguration {
        let profile = env.session.profile
        let state = env.badge.state
        let front = state.mode == .idle ? nil : state.frontTag
        return BadgeConfiguration(
            name: profile?.displayName ?? "Your name",
            tags: BadgeConfiguration.orderedTags(profile?.badgeTags ?? [], front: front),
            frontTag: front,
            mode: state.mode,
            glow: state.glow,
            matchColor: state.mode == .idle ? nil : state.color.map(Color.init(hex:)),
            presentation: presentation,
            layout: layout
        )
    }
}
