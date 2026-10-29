import Foundation

/// Group encounters on the mock: one group with Maya and Daniel earlier today,
/// so the People list shows a group row and its page (previews and UI tests).
extension MockBackend {
    static let mockGroupId = "g1"

    static var mockGroup: GroupEncounterDetail {
        let now = Date().timeIntervalSince1970 * 1000
        let start = now - 45 * 60_000
        let maya = people[0], daniel = people[1]
        return GroupEncounterDetail(
            id: mockGroupId, startedAt: start, endedAt: start + 9 * 60_000, durationMs: 9 * 60_000,
            myDurationMs: 8 * 60_000,
            summary: "Maya, Daniel and you swapped notes on testing agents in the wild. Maya wants an iOS engineer for a design tool side project; Daniel offered his evals harness for your badge agent.",
            topics: ["Agent evals", "Design tools", "iOS"],
            memberCount: 3,
            members: [
                GroupPerson(id: maya.id, name: maya.name, headline: maya.headline, company: maya.company,
                            avatarShape: maya.avatarShape, avatarColor: maya.avatarColor, profilePhotoUrl: nil,
                            present: false, joinedAt: start, leftAt: start + 9 * 60_000, matched: true,
                            color: "#87D9FB", saved: true),
                GroupPerson(id: daniel.id, name: daniel.name, headline: daniel.headline, company: daniel.company,
                            avatarShape: daniel.avatarShape, avatarColor: daniel.avatarColor, profilePhotoUrl: nil,
                            present: false, joinedAt: start + 60_000, leftAt: start + 9 * 60_000, matched: false,
                            color: nil, saved: false),
            ],
            followUp: "Hi Maya and Daniel! Loved the evals chat. Want to try the badge agent on Daniel's harness next week?",
            highlights: [
                "Daniel: we replay real conversations to test agents.",
                "Maya: the design tool needs a native iOS app.",
                "You: the badge already transcribes on device.",
            ],
            hasTranscript: true
        )
    }

    static var mockGroupSummary: GroupEncounterSummary {
        let g = mockGroup
        return GroupEncounterSummary(id: g.id, startedAt: g.startedAt, endedAt: g.endedAt, durationMs: g.durationMs,
                                     myDurationMs: g.myDurationMs, summary: g.summary, topics: g.topics,
                                     memberCount: g.memberCount, members: g.members)
    }

    func groupEncounters(userId: String) -> AsyncThrowingStream<[GroupEncounterSummary], Error> {
        AsyncThrowingStream { $0.yield([Self.mockGroupSummary]) }
    }

    func groupEncounter(userId: String, encounterId: String) -> AsyncThrowingStream<GroupEncounterDetail?, Error> {
        AsyncThrowingStream { $0.yield(encounterId == Self.mockGroupId ? Self.mockGroup : nil) }
    }

    func uploadTranscript(userId: String, conversationId: String, transcript: String?, startedAt: Date?,
                          leaving: Bool) async throws {}

    /// The group encounter as it shows on a member's page: the others who were there.
    static func mockGroupEncounter(on personId: String) -> Encounter? {
        let g = mockGroup
        guard g.members.contains(where: { $0.id == personId }) else { return nil }
        let others = g.members.filter { $0.id != personId }.map {
            EncounterPerson(id: $0.id, name: $0.name, avatarShape: $0.avatarShape, avatarColor: $0.avatarColor,
                            profilePhotoUrl: nil)
        }
        return Encounter(id: g.id, startedAt: g.startedAt, endedAt: g.endedAt, durationMs: g.myDurationMs ?? g.durationMs,
                         matched: true, summary: g.summary, topics: g.topics, followUp: g.followUp,
                         group: true, others: others)
    }
}
