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
    @State private var query = PeopleQuery()
    @AppStorage("people.groupBy") private var grouping: PeopleQuery.Grouping = .none
    @State private var showCustomDates = false

    var body: some View {
        @Bindable var router = env.router
        NavigationSplitView(columnVisibility: $columns) {
            sidebar(selection: $router.selectedPersonId)
        } detail: {
            if let id = router.selectedPersonId, let groupId = GroupNames.encounterId(fromSelection: id) {
                GroupDetailView(encounterId: groupId)
            } else if let id = router.selectedPersonId {
                PersonDetailView(personId: id)
            } else {
                NoPersonSelected(hasPeople: !people.isEmpty)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: env.session.userId) { await load() }
    }

    private func sidebar(selection: Binding<String?>) -> some View {
        let shown = filtered
        return List(selection: selection) {
            // Share requests waiting for my answer
            if !env.sharing.inbox.isEmpty && search.isEmpty {
                Section("Waiting for you") {
                    ForEach(env.sharing.inbox) { request in
                        ShareRequestCard(request: request, fromName: request.from?.displayName ?? "Someone",
                                         from: request.from)
                            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                }
            }
            if query.isFiltering && !people.isEmpty {
                filterSummary(shown: shown.count)
            }
            // Group encounters (three or more together), GroupViews.swift
            if !query.isFiltering {
                GroupEncountersSection(search: search)
            }
            ForEach(query.groups(shown, by: grouping)) { group in
                Section {
                    ForEach(group.people) { person in
                        NavigationLink(value: person.id) { PersonRow(person: person) }
                    }
                } header: {
                    if let title = group.title { Text(title) }
                }
            }
        }
        .overlay {
            if people.isEmpty {
                ContentUnavailableView(
                    "No one yet",
                    systemImage: "person.2",
                    description: Text("People you meet show up here, with a summary after you talk.")
                )
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .searchable(text: $search, prompt: "Name, company, topic or note")
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PeopleFilterMenu(query: $query, grouping: $grouping, showCustomDates: $showCustomDates)
            }
        }
        .sheet(isPresented: $showCustomDates) { PeopleDateRangeSheet(query: $query) }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: query)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: grouping)
        .navigationSplitViewColumnWidth(min: theme.sidebarMinWidth, ideal: theme.sidebarIdealWidth,
                                        max: theme.sidebarMaxWidth)
    }

    /// "4 of 9 · Matches, Met in person" with a Clear button.
    private func filterSummary(shown: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(theme.inkSecondary)
            Text("\(shown) of \(people.count), \(query.activeLabels.joined(separator: ", "))")
                .font(theme.caption).foregroundStyle(theme.inkSecondary).lineLimit(2)
            Spacer()
            Button("Clear") {
                Feedback.shared.play(.buttonPress)
                query.clear()
            }
            .font(theme.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
        .listRowBackground(Color.clear)
    }

    /// Search (name, role, company, tags, topics, notes) and filters.
    private var filtered: [PersonSummary] {
        query.apply(people, search: search)
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
            PersonPhoto(url: person.profilePhotoURL, avatar: person.avatar, seed: AvatarStyle.seed(person.id))
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.displayName).font(theme.headline)
                    if person.sharedWithMe == true {
                        Image(systemName: "person.crop.rectangle.stack.fill")
                            .font(theme.caption).foregroundStyle(theme.plezi)
                            .accessibilityLabel("Shared info with you")
                    }
                }
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
