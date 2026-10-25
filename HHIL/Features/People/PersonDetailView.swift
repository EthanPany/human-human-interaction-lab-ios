import SwiftUI

/// One person: who they are, what you talked about, what to do next, and the timeline.
/// Live: the summary appears as soon as Claude finishes it.
struct PersonDetailView: View {
    let personId: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.theme) private var theme
    @State private var detail: PersonDetail?

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    header(detail.person)
                    summary(detail.conversation)
                    followUp(detail.conversation)
                    timeline(detail.timeline)
                }
                .padding(theme.screenPadding)
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .background(theme.background)
        .navigationTitle(detail?.person.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: personId) { await load() }
    }

    private func header(_ p: PersonProfile) -> some View {
        HStack(spacing: 14) {
            Circle().fill(theme.surfaceMuted).frame(width: 64, height: 64)
                .overlay(Text((p.name ?? "?").prefix(1)).font(.title2.bold()))
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name ?? "Someone").font(theme.title)
                if let h = p.headline { Text(h).foregroundStyle(theme.inkSecondary) }
                FlowLayout(spacing: 6) {
                    ForEach(p.tags, id: \.self) { TagChip(text: $0, size: 13, fill: theme.surfaceMuted) }
                }
            }
        }
    }

    @ViewBuilder
    private func summary(_ c: ConversationInfo?) -> some View {
        Card {
            SectionLabel(text: "Summary")
            Text(c?.summary ?? "Your summary appears here after you talk.")
                .font(theme.body)
                .foregroundStyle(c?.summary == nil ? theme.inkSecondary : theme.ink)
            if let topics = c?.topics, !topics.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(topics, id: \.self) { TagChip(text: $0, size: 13, fill: theme.surfaceMuted) }
                }
            }
        }
    }

    @ViewBuilder
    private func followUp(_ c: ConversationInfo?) -> some View {
        if let followUp = c?.followUp {
            Card {
                SectionLabel(text: "Suggested follow up")
                Text(followUp).font(theme.body)
                ShareLink(item: followUp) {
                    Label("Copy or send", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func timeline(_ items: [TimelineItem]) -> some View {
        Card {
            SectionLabel(text: "Timeline")
            if items.isEmpty {
                Text("Nothing yet").foregroundStyle(theme.inkSecondary)
            }
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.date, style: .time)
                        .font(.footnote).foregroundStyle(theme.inkSecondary)
                        .frame(width: 70, alignment: .leading)
                    Text(item.text).font(theme.body)
                }
            }
        }
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
