import Foundation

// Group encounters: three or more badge wearers together share one encounter
// (spacetime/src/api/groups.ts in the parent repo). A pair is a group of two.

/// Someone else in my encounter right now (`badge:state` members).
struct BadgeMember: Decodable, Equatable, Identifiable {
    let id: String
    var name: String?
    var avatarShape: String?
    var avatarColor: String?
    /// We are a match: their color joins the badge's tint. Others join without it.
    var matched: Bool
    /// Our shared pair color (matches only).
    var color: String?
    /// When they joined the encounter (ms since 1970).
    var joinedAt: Double
    /// Their answer to "record this conversation?" (California mode), nil until they answer.
    var consent: Bool? = nil

    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
    var displayName: String { name?.split(separator: " ").first.map(String.init) ?? "Someone" }
}

/// One person in a group encounter row or page.
struct GroupPerson: Decodable, Identifiable, Hashable {
    let id: String
    var name: String?
    var headline: String?
    var company: String?
    var avatarShape: String?
    var avatarColor: String?
    var profilePhotoUrl: String?
    /// With the group right now (ongoing encounters).
    var present: Bool? = nil
    // groups:detail only
    var joinedAt: Double? = nil
    var leftAt: Double? = nil
    var matched: Bool? = nil
    var color: String? = nil
    var saved: Bool? = nil

    var displayName: String { name ?? "Someone" }
    var firstName: String { name?.split(separator: " ").first.map(String.init) ?? "Someone" }
    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
    var profilePhotoURL: URL? { profilePhotoUrl.flatMap(URL.init(string:)) }

    static func == (l: GroupPerson, r: GroupPerson) -> Bool {
        l.id == r.id && l.name == r.name && l.avatarShape == r.avatarShape && l.avatarColor == r.avatarColor
            && l.profilePhotoUrl == r.profilePhotoUrl && l.present == r.present && l.saved == r.saved
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A group encounter in the People list (`groups:list`).
struct GroupEncounterSummary: Decodable, Identifiable, Hashable {
    let id: String
    var startedAt: Double
    var endedAt: Double?
    /// How long the group was together, and how long I was with it (ms).
    var durationMs: Double
    var myDurationMs: Double?
    var summary: String?
    var topics: [String]
    /// Everyone, me included.
    var memberCount: Int
    /// The others, first joined first.
    var members: [GroupPerson]

    var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
    var isOngoing: Bool { endedAt == nil }
    var minutes: Int { Int(((myDurationMs ?? durationMs) / 60_000).rounded()) }
    /// "Maya, Leo and Sam".
    var names: String { GroupNames.join(members.map(\.firstName)) }

    static func == (l: GroupEncounterSummary, r: GroupEncounterSummary) -> Bool {
        l.id == r.id && l.endedAt == r.endedAt && l.summary == r.summary && l.members == r.members && l.topics == r.topics
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One group encounter's page (`groups:detail`).
struct GroupEncounterDetail: Decodable, Identifiable {
    let id: String
    var startedAt: Double
    var endedAt: Double?
    var durationMs: Double
    var myDurationMs: Double?
    var summary: String?
    var topics: [String]
    var memberCount: Int
    var members: [GroupPerson]
    /// My own follow up idea.
    var followUp: String?
    /// A few moments or quotes from the transcript.
    var highlights: [String]
    var hasTranscript: Bool?

    var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
    var isOngoing: Bool { endedAt == nil }
    var minutes: Int { Int(((myDurationMs ?? durationMs) / 60_000).rounded()) }
    var names: String { GroupNames.join(members.map(\.firstName)) }
}

/// Someone else who was there, on a person's encounter (`people:detail` others).
struct EncounterPerson: Decodable, Identifiable, Hashable {
    let id: String
    var name: String?
    var avatarShape: String?
    var avatarColor: String?
    var profilePhotoUrl: String?

    var firstName: String { name?.split(separator: " ").first.map(String.init) ?? "Someone" }
    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
}

enum GroupNames {
    /// "Maya", "Maya and Leo", "Maya, Leo and Sam", "Maya, Leo, Sam and 2 others".
    static func join(_ names: [String]) -> String {
        switch names.count {
        case 0: return "them"
        case 1: return names[0]
        case 2...4: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        default: return names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) others"
        }
    }

    /// Selection ids in People: a person's id, or this prefix plus a group encounter id.
    static let selectionPrefix = "group:"

    static func selection(_ encounterId: String) -> String { selectionPrefix + encounterId }

    static func encounterId(fromSelection id: String) -> String? {
        id.hasPrefix(selectionPrefix) ? String(id.dropFirst(selectionPrefix.count)) : nil
    }
}
