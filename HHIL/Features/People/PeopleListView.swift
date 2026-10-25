import SwiftUI

/// People you met in person or saved, newest first. Updates live: someone
/// shows up the moment you meet, before anything else is known about them.
///
/// A sidebar and a detail column. On a phone (and a folded iPhone Duo, whose
/// width is compact) the split collapses into a stack and tapping a person
/// pushes their page. On iPad, landscape and the unfolded Duo the list stays
/// on the left and the selected person's page sits beside it.
struct PeopleListView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var people: [PersonSummary] = []
    @State private var search = ""
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var router = env.router
        NavigationSplitView(columnVisibility: $columns) {
            sidebar(selection: $router.selectedPersonId)
        } detail: {
            if let id = router.selectedPersonId {
                PersonDetailView(personId: id)
            } else {
                NoPersonSelected(hasPeople: !people.isEmpty)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: env.session.userId) { await load() }
    }

    private func sidebar(selection: Binding<String?>) -> some View {
        List(filtered, selection: selection) { person in
            NavigationLink(value: person.id) { PersonRow(person: person) }
        }
        .overlay {
            if people.isEmpty {
                ContentUnavailableView(
                    "No one yet",
                    systemImage: "person.2",
                    description: Text("People you meet show up here, with a summary after you talk.")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .searchable(text: $search, prompt: "Search people")
        .navigationTitle("People")
        .navigationSplitViewColumnWidth(min: theme.sidebarMinWidth, ideal: theme.sidebarIdealWidth,
                                        max: theme.sidebarMaxWidth)
    }

    private var filtered: [PersonSummary] {
        guard !search.isEmpty else { return people }
        return people.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || ($0.headline ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    private func load() async {
        guard let userId = env.session.userId else { return }
        do {
            for try await list in env.backend.people(userId: userId) { people = list }
        } catch {
            print("people stream ended:", error)
        }
    }
}

/// The detail column before anyone is picked (wide screens only: on a phone
/// the list is showing instead).
private struct NoPersonSelected: View {
    var hasPeople: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            FlowingBackground(flow: 0.4)
            VStack(spacing: 14) {
                AvatarView(shape: .blob, color: theme.yellowStrong, expression: .happy,
                           animated: true, seed: 7)
                    .frame(width: 96, height: 96)
                Text(hasPeople ? "Pick someone to catch up" : "No one here yet")
                    .font(theme.title)
                    .foregroundStyle(theme.strongInk)
                    .multilineTextAlignment(.center)
                Text(hasPeople
                     ? "Choose a person from the list to see who they are and what you talked about."
                     : "Wear your badge and walk around. Everyone you meet lands in the list, with a summary after you talk.")
                    .font(theme.body)
                    .foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: theme.readableCardWidth * 0.75)
            .background(theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: theme.cornerRadius))
            .padding(theme.screenPadding)
        }
    }
}

private struct PersonRow: View {
    let person: PersonSummary
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(shape: person.avatar.shape, color: person.avatar.color,
                       expression: .happy, animated: false, seed: AvatarStyle.seed(person.id))
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(theme.headline)
                if let line = [person.headline, person.company].compactMap({ $0?.nilIfBlank }).joined(separator: " · ").nilIfBlank {
                    Text(line).font(theme.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                } else if let tags = person.tags.prefix(3).joined(separator: " · ").nilIfBlank {
                    Text(tags).font(theme.caption).foregroundStyle(theme.inkSecondary).lineLimit(1)
                }
                if let summary = person.lastSummary?.nilIfBlank {
                    Text(summary).font(theme.caption).foregroundStyle(theme.ink).lineLimit(2)
                } else if person.saved == false {
                    Text("Met in person").font(theme.caption).foregroundStyle(theme.inkSecondary)
                }
            }
            Spacer()
            Text(person.connectedDate, style: .time)
                .font(theme.caption).foregroundStyle(theme.inkSecondary)
        }
        .padding(.vertical, 4)
    }
}
