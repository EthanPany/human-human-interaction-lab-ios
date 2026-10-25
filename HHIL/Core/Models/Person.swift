import Foundation
import ConvexMobile

/// A row in the People list: someone I saved, or met in person.
struct PersonSummary: Decodable, Identifiable, Hashable {
    let id: String
    var name: String?
    var headline: String?
    var company: String?
    var location: String?
    var tags: [String]
    var avatarShape: String?
    var avatarColor: String?
    var photoUrl: String?
    /// When they joined my list (saved, or first met).
    @ConvexFloat var connectedAt: Double
    var lastSummary: String?
    /// False for people I met but haven't saved yet (nil from older servers).
    var saved: Bool? = nil

    var displayName: String { name ?? "Someone" }
    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
    var connectedDate: Date { Date(timeIntervalSince1970: connectedAt / 1000) }

    /// Same person with the same visible details (so a row redraws when its summary lands).
    static func == (l: PersonSummary, r: PersonSummary) -> Bool {
        l.id == r.id && l.name == r.name && l.headline == r.headline && l.company == r.company
            && l.tags == r.tags && l.lastSummary == r.lastSummary && l.saved == r.saved
            && l.connectedAt == r.connectedAt && l.avatarShape == r.avatarShape && l.avatarColor == r.avatarColor
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Public profile of another person.
struct PersonProfile: Decodable {
    let id: String
    var name: String?
    var headline: String?
    var company: String?
    var location: String?
    var tags: [String]
    var hobbies: [String]
    var avatarShape: String?
    var avatarColor: String?
    var photoUrl: String?

    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
    var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }
}

struct ConversationInfo: Decodable {
    @ConvexFloat var startedAt: Double
    @OptionalConvexFloat var endedAt: Double?
    var summary: String?
    var topics: [String]
    var followUp: String?

    var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
    var isOngoing: Bool { endedAt == nil }
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
    /// False when we met but I haven't saved their contact yet.
    var saved: Bool? = nil
}

/// Another phone at the event, with the Nearby Interaction token it made for us.
struct Peer: Decodable, Identifiable {
    let userId: String
    var name: String
    var tokenForMe: String?

    var id: String { userId }
}
