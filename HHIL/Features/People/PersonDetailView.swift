import SwiftUI

/// One person: who they are, every encounter (each with its summary and a
/// follow up), and the timeline.
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
                    sharing(d.person)
                    interests(d.person)
                }
                column {
                    encounters(d)
                    timeline(d.timeline)
                }
            }
        } else {
            VStack(spacing: 20) {
                identity(d.person)
                about(d)
                sharing(d.person)
                encounters(d)
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
            HStack(alignment: .center, spacing: 12) {
                // Their profile photo, when they set one (the card above keeps the jelly avatar)
                if let photo = p.profilePhotoURL {
                    PersonPhoto(url: photo, avatar: p.avatar, seed: AvatarStyle.seed(p.id))
                        .frame(width: 56, height: 56)
                }
                if let headline = p.headline?.nilIfBlank {
                    Text(headline).font(theme.body).foregroundStyle(theme.ink)
                }
            }
            if let location = p.location?.nilIfBlank { LocationPill(text: location) }
            HStack(spacing: 8) {
                Image(systemName: d.saved == false ? "figure.wave" : "person.crop.circle.badge.checkmark")
                    .foregroundStyle(theme.inkSecondary)
                Text(statusLine(d)).font(theme.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    /// Contact info both ways: what they share with me, Share my info, Request their info.
    private func sharing(_ p: PersonProfile) -> some View {
        PersonSharingCard(personId: p.id, name: p.name?.nilIfBlank ?? "Someone")
    }

    @ViewBuilder
    private func interests(_ p: PersonProfile) -> some View {
        let items = p.tags + p.hobbies.filter { !p.tags.contains($0) }
        if !items.isEmpty {
            InterestsCard(interests: items, highlighted: nil, moments: [], scale: 1)
        }
    }

    /// Every time we were together, newest first, each with its own summary
    /// and follow up. Coming back within 5 minutes is the same encounter.
    @ViewBuilder
    private func encounters(_ d: PersonDetail) -> some View {
        let list = Self.encounterList(d)
        if list.isEmpty {
            Card {
                SectionHeader(title: "Summary")
                Text("Your summary appears here after you talk.")
                    .font(theme.body).foregroundStyle(theme.inkSecondary)
            }
        } else {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, e in
                encounter(e, title: list.count > 1 ? "Encounter \(list.count - index)" : "Summary")
            }
        }
    }

    /// Older servers send only the latest conversation.
    private static func encounterList(_ d: PersonDetail) -> [Encounter] {
        if let list = d.encounters { return list }
        guard let c = d.conversation else { return [] }
        let end = c.endedAt ?? Date().timeIntervalSince1970 * 1000
        return [Encounter(id: "latest", startedAt: c.startedAt, endedAt: c.endedAt, durationMs: max(0, end - c.startedAt),
                          matched: true, summary: c.summary, topics: c.topics, followUp: c.followUp)]
    }

    private func encounter(_ e: Encounter, title: String) -> some View {
        VStack(spacing: 12) {
            Card {
                SectionHeader(title: title)
                Text(whenLine(e)).font(theme.caption).foregroundStyle(theme.inkSecondary)
                if let text = e.summary?.nilIfBlank {
                    Text(text).font(theme.body).foregroundStyle(theme.ink)
                } else if e.isOngoing {
                    Text("You're together now. Your summary appears here after you part ways.")
                        .font(theme.body).foregroundStyle(theme.inkSecondary)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Writing your summary").font(theme.body).foregroundStyle(theme.inkSecondary)
                    }
                }
                if !e.topics.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(e.topics, id: \.self) { TagChip(text: $0, systemImage: nil, size: 13) }
                    }
                }
            }
            followUp(e.followUp)
        }
    }

    /// "Today at 3:42 PM, 6 min together".
    private func whenLine(_ e: Encounter) -> String {
        let when = e.startedDate.formatted(date: .abbreviated, time: .shortened)
        if e.isOngoing { return "\(when), together now" }
        let length = e.minutes < 1 ? "under a minute" : "\(e.minutes) min"
        return "\(when), \(length) together"
    }

    @ViewBuilder
    private func followUp(_ text: String?) -> some View {
        if let followUp = text?.nilIfBlank {
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
