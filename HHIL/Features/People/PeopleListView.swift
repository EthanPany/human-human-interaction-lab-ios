import SwiftUI

/// People you saved (connected only), newest first. Updates live.
struct PeopleListView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var people: [PersonSummary] = []
    @State private var search = ""
    @State private var width: CGFloat = 0

    var body: some View {
        @Bindable var router = env.router
        NavigationStack(path: $router.peoplePath) {
            Group {
                if width >= theme.twoColumnWidth { grid } else { list }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No one yet",
                        systemImage: "person.2",
                        description: Text("People you meet and save by text show up here.")
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .searchable(text: $search, prompt: "Search people")
            .navigationTitle("People")
            .navigationDestination(for: String.self) { PersonDetailView(personId: $0) }
        }
        .task(id: env.session.userId) { await load() }
    }

    private var list: some View {
        List(filtered) { person in
            NavigationLink(value: person.id) { PersonRow(person: person) }
        }
    }

    /// Wide screens: the same rows as cards in a grid instead of one long row each.
    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: theme.gridCardMinWidth), spacing: 16)], spacing: 16) {
                ForEach(filtered) { person in
                    NavigationLink(value: person.id) {
                        PersonRow(person: person)
                            .padding(14)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
                    }
                    .buttonStyle(PressScaleStyle())
                    .foregroundStyle(theme.ink)
                }
            }
            .frame(maxWidth: theme.maxContentWidth)
            .padding(theme.screenPadding)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.bottom, 24, for: .scrollContent)
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
                }
            }
            Spacer()
            Text(person.connectedDate, style: .time)
                .font(theme.caption).foregroundStyle(theme.inkSecondary)
        }
        .padding(.vertical, 4)
    }
}
