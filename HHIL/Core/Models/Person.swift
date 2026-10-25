import Foundation
import ConvexMobile

/// A row in the People list.
struct PersonSummary: Decodable, Identifiable, Hashable {
    let id: String
    var name: String?
    var headline: String?
    var tags: [String]
    @ConvexFloat var connectedAt: Double
    var lastSummary: String?

    var displayName: String { name ?? "Someone" }
    var connectedDate: Date { Date(timeIntervalSince1970: connectedAt / 1000) }

    static func == (l: PersonSummary, r: PersonSummary) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Public profile of another person.
struct PersonProfile: Decodable {
    let id: String
    var name: String?
    var headline: String?
    var tags: [String]
    var hobbies: [String]
}

struct ConversationInfo: Decodable {
    @ConvexFloat var startedAt: Double
    @OptionalConvexFloat var endedAt: Double?
    var summary: String?
    var topics: [String]
    var followUp: String?

    var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
}

struct TimelineItem: Decodable, Identifiable {
    var kind: String
    var text: String
    @ConvexFloat var at: Double

    var id: String { "\(kind)-\(at)" }
    var date: Date { Date(timeIntervalSince1970: at / 1000) }
}

/// Everything the person detail screen shows.
struct PersonDetail: Decodable {
    var person: PersonProfile
    @OptionalConvexFloat var connectedAt: Double?
    var conversation: ConversationInfo?
    var timeline: [TimelineItem]
}

/// Another phone at the event, with the Nearby Interaction token it made for us.
struct Peer: Decodable, Identifiable {
    let userId: String
    var name: String
    var tokenForMe: String?

    var id: String { userId }
}
