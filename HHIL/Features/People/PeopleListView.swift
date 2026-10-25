import SwiftUI

/// People you saved (connected only), newest first. Updates live.
struct PeopleListView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var people: [PersonSummary] = []
    @State private var search = ""

    var body: some View {
        @Bindable var router = env.router
        NavigationStack(path: $router.peoplePath) {
            List(filtered) { person in
                NavigationLink(value: person.id) { PersonRow(person: person) }
            }
            .overlay {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No one yet",
                        systemImage: "person.2",
                        description: Text("People you meet and save by text show up here.")
                    )
                }
            }
            .searchable(text: $search, prompt: "Search people")
            .navigationTitle("People")
            .navigationDestination(for: String.self) { PersonDetailView(personId: $0) }
        }
        .task(id: env.session.userId) { await load() }
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
            Circle().fill(theme.surfaceMuted).frame(width: 42, height: 42)
                .overlay(Text(person.displayName.prefix(1)).font(.headline))
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(theme.headline)
                if let headline = person.headline {
                    Text(headline).font(.subheadline).foregroundStyle(theme.inkSecondary).lineLimit(1)
                }
            }
            Spacer()
            Text(person.connectedDate, style: .time)
                .font(.footnote).foregroundStyle(theme.inkSecondary)
        }
        .padding(.vertical, 4)
    }
}
