import SwiftUI

// Group encounters in People (three or more together): a group row in the
// list, the group's own page, and the "with ..." line on a person's encounter.
// Kept in their own file so the People list and person page only plug them in.

/// The "Groups" section of the People list: one row per group encounter.
struct GroupEncountersSection: View {
    var search: String
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let shown = filtered
        if !shown.isEmpty {
            Section("Groups") {
                ForEach(shown) { group in
                    NavigationLink(value: GroupNames.selection(group.id)) { GroupRow(group: group) }
                }
            }
        }
    }

    /// Search names, summaries and topics, like the people rows.
    private var filtered: [GroupEncounterSummary] {
        let groups = env.groups.encounters
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.filter { g in
            let text = ([g.summary ?? ""] + g.topics + g.members.flatMap { [$0.name ?? "", $0.company ?? ""] })
                .joined(separator: " ").lowercased()
            return text.contains(q)
        }
    }
}

/// Overlapping round avatars (or photos): up to `limit`, then a "+N" disc.
struct StackedAvatars: View {
    var people: [GroupPerson]
    var size: CGFloat = 30
    var limit = 3
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: -size * 0.36) {
            ForEach(people.prefix(limit)) { p in
                PersonPhoto(url: p.profilePhotoURL, avatar: p.avatar, seed: AvatarStyle.seed(p.id))
                    .frame(width: size, height: size)
                    .background(Circle().fill(theme.surface).padding(-2))
            }
            if people.count > limit {
                Text("+\(people.count - limit)")
                    .font(theme.caption.weight(.bold))
                    .foregroundStyle(theme.strongInk)
                    .frame(width: size, height: size)
                    .background(Circle().fill(theme.surfaceMuted))
                    .overlay(Circle().strokeBorder(theme.surface, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GroupNames.join(people.map(\.firstName)))
    }
}

/// A group encounter in the People list: stacked avatars, names, time, summary.
private struct GroupRow: View {
    let group: GroupEncounterSummary
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            StackedAvatars(people: group.members, size: 32, limit: 2)
                .frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.names).font(theme.headline).lineLimit(1)
                Text(detailLine).font(theme.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                if let summary = group.summary?.nilIfBlank {
                    Text(summary).font(theme.caption).foregroundStyle(theme.ink).lineLimit(2)
                }
            }
            Spacer()
            Text(group.startedDate, style: .time)
                .font(theme.caption).foregroundStyle(theme.inkSecondary)
        }
        .padding(.vertical, 4)
    }

    private var detailLine: String {
        let people = "\(group.memberCount) people"
        if group.isOngoing { return "\(people), together now" }
        return "\(people), \(group.minutes < 1 ? "under a minute" : "\(group.minutes) min")"
    }
}

/// On a person's encounter: who else was there, and a way into the group's page.
struct EncounterGroupLine: View {
    let encounter: Encounter
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme

    var body: some View {
        let others = encounter.others ?? []
        Button {
            env.router.selectedPersonId = GroupNames.selection(encounter.id)
        } label: {
            HStack(spacing: 10) {
                StackedAvatars(people: others.map {
                    GroupPerson(id: $0.id, name: $0.name, avatarShape: $0.avatarShape, avatarColor: $0.avatarColor,
                                profilePhotoUrl: $0.profilePhotoUrl)
                }, size: 24)
                Text(others.isEmpty ? "In a group" : "Also there: \(GroupNames.join(others.map(\.firstName)))")
                    .font(theme.caption.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(theme.caption.weight(.semibold))
                    .foregroundStyle(theme.inkSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.surfaceMuted, in: RoundedRectangle(cornerRadius: theme.cornerRadius * 0.75))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityHint("Opens the group")
    }
}

/// One group encounter: who was there, the summary, highlights from the
/// transcript, my follow up idea, and a link to each member's page.
struct GroupDetailView: View {
    let encounterId: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var detail: GroupEncounterDetail?
    @State private var loaded = false

    var body: some View {
        ZStack {
            FlowingBackground(flow: 0.4)
            ScrollView {
                if let detail {
                    VStack(spacing: 20) {
                        header(detail)
                        summary(detail)
                        highlights(detail)
                        followUp(detail.followUp)
                        members(detail)
                    }
                    .frame(maxWidth: theme.readableCardWidth)
                    .padding(.horizontal, theme.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                } else if loaded {
                    ContentUnavailableView("Group not found", systemImage: "person.3",
                                           description: Text("This group isn't in your People anymore."))
                        .padding(.top, 60)
                } else {
                    ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
                }
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
        }
        .navigationTitle(detail?.names ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: encounterId) {
            if detail?.id != encounterId { detail = nil; loaded = false }
            await load()
        }
    }

    private func header(_ d: GroupEncounterDetail) -> some View {
        Card {
            StackedAvatars(people: d.members, size: 56, limit: 4)
            Text("You, \(d.names)")
                .font(theme.title)
                .foregroundStyle(theme.strongInk)
            Text(whenLine(d)).font(theme.caption).foregroundStyle(theme.inkSecondary)
            if !d.topics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(d.topics, id: \.self) { TagChip(text: $0, systemImage: nil, size: 13) }
                }
            }
        }
    }

    private func summary(_ d: GroupEncounterDetail) -> some View {
        Card {
            SectionHeader(title: "Summary")
            if let text = d.summary?.nilIfBlank {
                Text(text).font(theme.body).foregroundStyle(theme.ink)
            } else if d.isOngoing {
                Text("You're together now. The summary for everyone appears here after the group parts.")
                    .font(theme.body).foregroundStyle(theme.inkSecondary)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Writing the group's summary").font(theme.body).foregroundStyle(theme.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func highlights(_ d: GroupEncounterDetail) -> some View {
        if !d.highlights.isEmpty {
            Card(fill: theme.yellow) {
                SectionHeader(title: "Highlights")
                ForEach(Array(d.highlights.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "quote.opening")
                            .font(theme.caption.weight(.bold))
                            .foregroundStyle(theme.ink)
                        Text(line).font(theme.body).foregroundStyle(theme.ink)
                    }
                }
            }
        }
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

    private func members(_ d: GroupEncounterDetail) -> some View {
        Card {
            SectionHeader(title: "Who was there")
            ForEach(d.members) { m in
                Button {
                    env.router.selectedPersonId = m.id
                } label: {
                    HStack(spacing: 12) {
                        PersonPhoto(url: m.profilePhotoURL, avatar: m.avatar, seed: AvatarStyle.seed(m.id))
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(m.displayName).font(theme.headline).foregroundStyle(theme.strongInk)
                                if m.matched == true {
                                    // Our shared match color, as on the badge
                                    Circle().fill(m.color.map(Color.init(hex:)) ?? theme.yellowStrong)
                                        .frame(width: 9, height: 9)
                                        .accessibilityLabel("A match")
                                }
                            }
                            if let line = [m.headline, m.company].compactMap({ $0?.nilIfBlank }).joined(separator: " · ").nilIfBlank {
                                Text(line).font(theme.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                            }
                            Text(statusLine(m)).font(theme.caption).foregroundStyle(theme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(theme.caption.weight(.semibold))
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
            }
        }
    }

    // MARK: Helpers

    private func whenLine(_ d: GroupEncounterDetail) -> String {
        let when = d.startedDate.formatted(date: .abbreviated, time: .shortened)
        if d.isOngoing { return "\(when), together now" }
        let length = d.minutes < 1 ? "under a minute" : "\(d.minutes) min"
        return "\(when), \(length) together, \(d.memberCount) people"
    }

    private func statusLine(_ m: GroupPerson) -> String {
        var parts: [String] = []
        if m.present == true { parts.append("Here now") }
        if let joined = m.joinedAt {
            parts.append("Joined \(Date(timeIntervalSince1970: joined / 1000).formatted(date: .omitted, time: .shortened))")
        }
        parts.append(m.saved == true ? "In your people" : "Met in this group")
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let userId = env.session.userId else { return }
        do {
            for try await d in env.backend.groupEncounter(userId: userId, encounterId: encounterId) {
                detail = d
                loaded = true
            }
        } catch {
            loaded = true
            print("group stream ended:", error)
        }
    }
}
