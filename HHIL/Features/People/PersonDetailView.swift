import SwiftUI

/// One person: who they are, what you talked about, what to do next, and the timeline.
/// Live: the summary appears as soon as Claude finishes it.
///
/// Laid out like the Profile tab: the same identity card and interests block,
/// as cards with a readable width. One column in a narrow column (a phone, a
/// folded Duo, or the detail side of a split on a smaller iPad), two side by
/// side when the column is wide.
struct PersonDetailView: View {
    let personId: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var detail: PersonDetail?
    @State private var width: CGFloat = 0

    var body: some View {
        ZStack {
            FlowingBackground(flow: 0.4)
            ScrollView {
                if let detail {
                    columns(detail)
                        .frame(maxWidth: twoColumns ? theme.detailMaxWidth : theme.readableCardWidth)
                        .padding(.horizontal, theme.screenPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
                }
            }
            // Room to scroll the last card clear of the floating tab bar
            .contentMargins(.bottom, 24, for: .scrollContent)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle(detail?.person.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: personId) {
            // Picking someone else in the sidebar: don't show the last person meanwhile
            if detail?.person.id != personId { detail = nil }
            await load()
        }
    }

    // MARK: Layout

    private var twoColumns: Bool { width >= theme.detailTwoColumnWidth }

    @ViewBuilder
    private func columns(_ d: PersonDetail) -> some View {
        if twoColumns {
            HStack(alignment: .top, spacing: 20) {
                column {
                    identity(d.person)
                    about(d)
                    followUp(d.conversation)
                }
                column {
                    summary(d.conversation)
                    interests(d.person)
                    timeline(d.timeline)
                }
            }
        } else {
            VStack(spacing: 20) {
                identity(d.person)
                about(d)
                summary(d.conversation)
                followUp(d.conversation)
                interests(d.person)
                timeline(d.timeline)
            }
        }
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 20) { content() }
            .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: Blocks

    private func identity(_ p: PersonProfile) -> some View {
        IdentityCard(c: configuration(p), scale: 0.91, nameSize: 76,
                     avatarSpace: 112, minHeight: 230)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Role, where they're from, and how they got into your list. People you
    /// only met may have little more than a name.
    private func about(_ d: PersonDetail) -> some View {
        let p = d.person
        return Card {
            if let headline = p.headline?.nilIfBlank {
                Text(headline).font(theme.body).foregroundStyle(theme.ink)
            }
            if let location = p.location?.nilIfBlank { LocationPill(text: location) }
            HStack(spacing: 8) {
                Image(systemName: d.saved == false ? "figure.wave" : "person.crop.circle.badge.checkmark")
                    .foregroundStyle(theme.inkSecondary)
                Text(statusLine(d)).font(theme.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private func interests(_ p: PersonProfile) -> some View {
        let items = p.tags + p.hobbies.filter { !p.tags.contains($0) }
        if !items.isEmpty {
            InterestsCard(interests: items, highlighted: nil, moments: [], scale: 1)
        }
    }

    private func summary(_ c: ConversationInfo?) -> some View {
        Card {
            SectionHeader(title: "Summary")
            if let text = c?.summary?.nilIfBlank {
                Text(text).font(theme.body).foregroundStyle(theme.ink)
            } else if let c, c.isOngoing {
                Text("You're talking now. Your summary appears here after you part ways.")
                    .font(theme.body).foregroundStyle(theme.inkSecondary)
            } else if c != nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Writing your summary").font(theme.body).foregroundStyle(theme.inkSecondary)
                }
            } else {
                Text("Your summary appears here after you talk.")
                    .font(theme.body).foregroundStyle(theme.inkSecondary)
            }
            if let topics = c?.topics, !topics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(topics, id: \.self) { TagChip(text: $0, systemImage: nil, size: 13) }
                }
            }
        }
    }

    @ViewBuilder
    private func followUp(_ c: ConversationInfo?) -> some View {
        if let followUp = c?.followUp?.nilIfBlank {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Suggested follow up")
                Text(followUp).font(theme.body).foregroundStyle(theme.ink)
                ShareLink(item: followUp) {
                    Label("Copy or send", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.blue, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
        }
    }

    private func timeline(_ items: [TimelineItem]) -> some View {
        Card {
            SectionHeader(title: "Timeline")
            if items.isEmpty {
                Text("Nothing yet").font(theme.body).foregroundStyle(theme.inkSecondary)
            }
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.date, style: .time)
                        .font(theme.caption).foregroundStyle(theme.inkSecondary)
                        .frame(width: 70, alignment: .leading)
                    Text(item.text).font(theme.body).foregroundStyle(theme.ink)
                }
            }
        }
    }

    // MARK: Helpers

    private func statusLine(_ d: PersonDetail) -> String {
        let met = d.connectedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        let when = met.map { $0.formatted(date: .abbreviated, time: .shortened) }
        switch (d.saved == false, when) {
        case (true, let when?): return "Met in person, \(when)"
        case (true, nil): return "Met in person"
        case (false, let when?): return "In your people since \(when)"
        case (false, nil): return "In your people"
        }
    }

    /// Their identity card as the Profile tab draws yours, without anyone nearby.
    private func configuration(_ p: PersonProfile) -> BadgeConfiguration {
        BadgeConfiguration(
            name: p.name?.nilIfBlank ?? "Someone",
            company: p.company?.nilIfBlank,
            role: p.headline?.nilIfBlank,
            location: p.location?.nilIfBlank,
            layout: p.photoURL != nil ? .photoText : .avatar,
            photoURL: p.photoURL,
            avatar: p.avatar,
            seed: AvatarStyle.seed(p.id),
            hasProfile: p.name?.nilIfBlank != nil,
            interests: [],
            tags: p.tags,
            moments: [],
            frontTag: nil,
            mode: .idle,
            closeness: 0,
            matchColor: nil,
            peerAvatar: nil,
            peerSeed: 0,
            look: nil,
            followsTilt: false,
            presentation: .window,
            orientation: .vertical
        )
    }

    private func load() async {
        guard let userId = env.session.userId else { return }
        do {
            for try await d in env.backend.personDetail(userId: userId, otherId: personId) { detail = d }
        } catch {
            print("person detail stream ended:", error)
        }
    }
}
