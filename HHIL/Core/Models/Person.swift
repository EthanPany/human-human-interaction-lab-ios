import Foundation

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
    var connectedAt: Double
    var lastSummary: String?
    /// False for people I met but haven't saved yet (nil from older servers).
    var saved: Bool? = nil
    /// Their square profile photo (nil: show the jelly avatar).
    var profilePhotoUrl: String? = nil
    /// The pair's match score (0...1) and whether it clears the threshold.
    var matchScore: Double? = nil
    var matched: Bool? = nil
    /// First time we were together in person (nil: never met in person).
    var metAt: Double? = nil
    var encounterCount: Int? = nil
    /// Topics from every encounter, and every summary (search).
    var topics: [String]? = nil
    var notes: String? = nil
    /// They share contact info with me / I share mine with them.
    var sharedWithMe: Bool? = nil
    var sharedByMe: Bool? = nil

    var displayName: String { name ?? "Someone" }
    var profilePhotoURL: URL? { profilePhotoUrl.flatMap(URL.init(string:)) }
    var metDate: Date? { metAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
    var connectedDate: Date { Date(timeIntervalSince1970: connectedAt / 1000) }

    /// Same person with the same visible details (so a row redraws when its summary lands).
    static func == (l: PersonSummary, r: PersonSummary) -> Bool {
        l.id == r.id && l.name == r.name && l.headline == r.headline && l.company == r.company
            && l.tags == r.tags && l.lastSummary == r.lastSummary && l.saved == r.saved
            && l.connectedAt == r.connectedAt && l.avatarShape == r.avatarShape && l.avatarColor == r.avatarColor
            && l.profilePhotoUrl == r.profilePhotoUrl && l.matched == r.matched && l.metAt == r.metAt
            && l.sharedWithMe == r.sharedWithMe && l.sharedByMe == r.sharedByMe && l.topics == r.topics
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
    /// Square profile photo (nil: the jelly avatar).
    var profilePhotoUrl: String? = nil

    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
    var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }
    var profilePhotoURL: URL? { profilePhotoUrl.flatMap(URL.init(string:)) }
}

struct ConversationInfo: Decodable {
    var startedAt: Double
    var endedAt: Double?
    var summary: String?
    var topics: [String]
    var followUp: String?

    var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
    var isOngoing: Bool { endedAt == nil }
}

/// One time together with someone. Coming back within 5 minutes continues the
/// same encounter; later is a new one with its own summary.
struct Encounter: Decodable, Identifiable {
    let id: String
    var startedAt: Double
    var endedAt: Double?
    /// Time actually spent together (milliseconds).
    var durationMs: Double
    /// We were a match (false: we just stood together).
    var matched: Bool
    var summary: String?
    var topics: [String]
    var followUp: String?
    /// A group encounter (three or more), and who else was there besides this person (Group.swift).
    var group: Bool? = nil
    var others: [EncounterPerson]? = nil

    var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
    var isOngoing: Bool { endedAt == nil }
    var minutes: Int { Int((durationMs / 60_000).rounded()) }
    var isGroup: Bool { group == true }
}

struct TimelineItem: Decodable, Identifiable {
    var kind: String
    var text: String
    var at: Double

    var id: String { "\(kind)-\(at)" }
    var date: Date { Date(timeIntervalSince1970: at / 1000) }
}

/// Everything the person detail screen shows.
struct PersonDetail: Decodable {
    var person: PersonProfile
    var connectedAt: Double?
    var conversation: ConversationInfo?
    /// Every encounter, newest first (nil from older servers: use `conversation`).
    var encounters: [Encounter]? = nil
    var timeline: [TimelineItem]
    /// False when we met but I haven't saved their contact yet.
    var saved: Bool? = nil
}

/// Another phone at the event, with the Nearby Interaction token it made for us.
struct Peer: Decodable, Identifiable {
    let userId: String
    var name: String
    var tokenForMe: String?
    /// A match (ranged first). The server sends peers most important first.
    var isMatch: Bool? = nil
    /// The server's ranking (higher first): with me, matches in the area,
    /// others in the area, unknown, away. Nil from older servers (use the order).
    var priority: Double? = nil
    /// The server knows they are around (a fresh distance, or Bluetooth hears them).
    var inArea: Bool? = nil
    /// The short id their badge advertises over Bluetooth right now (rotates).
    var bleId: String? = nil
    /// The pair's distance merged from both phones, its source (uwb or ble) and age.
    var meters: Double? = nil
    var source: String? = nil
    var ageMs: Double? = nil
    /// Matches only: the shared pair color and their avatar color (edge glows).
    var color: String? = nil
    var avatarColor: String? = nil

    var id: String { userId }
}
