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
        .background(FlowingBackground(flow: 0.4))
        .navigationTitle(detail?.person.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: personId) { await load() }
    }

    private func header(_ p: PersonProfile) -> some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(p.name ?? "Someone").font(.brand(40, .semibold)).foregroundStyle(theme.strongInk)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if let line = [p.company, p.headline].compactMap({ $0?.nilIfBlank }).joined(separator: " | ").nilIfBlank {
                        Text(line).font(theme.body).foregroundStyle(theme.ink)
                    }
                    if let location = p.location?.nilIfBlank { LocationPill(text: location) }
                }
                Spacer(minLength: 0)
                if let url = p.photoURL {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { p.avatar.color.opacity(0.3) }
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .bottomLeading) {
                            AvatarView(shape: p.avatar.shape, color: p.avatar.color, expression: .happy, seed: AvatarStyle.seed(p.id))
                                .frame(width: 40, height: 40).offset(x: -14, y: 10)
                        }
                } else {
                    AvatarView(shape: p.avatar.shape, color: p.avatar.color, expression: .happy, seed: AvatarStyle.seed(p.id))
                        .frame(width: 96, height: 96)
                }
            }
            let interests = p.tags + p.hobbies.filter { !p.tags.contains($0) }
            if !interests.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(interests, id: \.self) { TagChip(text: $0, size: 14) }
                }
            }
        }
    }

    @ViewBuilder
    private func summary(_ c: ConversationInfo?) -> some View {
        Card {
            SectionLabel(text: "Summary")
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
        if let followUp = c?.followUp {
            Card(fill: theme.yellow) {
                SectionLabel(text: "Suggested follow up")
                Text(followUp).font(theme.body)
                ShareLink(item: followUp) {
                    Label("Copy or send", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
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
