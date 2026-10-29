import Foundation
import SwiftUI

/// The signed in person's profile. Every field is optional because people can
/// fill it by hand or let the text agent collect it over time.
struct UserProfile: Decodable, Identifiable {
    let id: String
    var phone: String
    var name: String?
    var headline: String?
    var company: String?
    var location: String?
    var tags: [String]?
    var lookingFor: String?
    var offers: String?
    var hobbies: [String]?
    var appearance: String?
    var californiaMode: Bool?
    var recordConversations: Bool?
    var hasPassword: Bool?
    var avatarShape: String?
    var avatarColor: String?
    var badgeLayout: String?
    var photoUrl: String?
    /// This person's Photon iMessage line (assigned at sign up).
    var agentLine: String? = nil
    /// False until they've texted the agent once (a shared line can't text first).
    var agentConnected: Bool? = nil
    /// Where my badge starts responding, meters (Settings > Nearby). Nil: the maximum.
    var respondFromM: Double? = nil
    /// Encounters under a minute leave no record (Settings > Recording). Nil: on.
    var dropShortEncounters: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case phone, name, headline, company, location, tags, lookingFor, offers, hobbies, appearance
        case californiaMode, recordConversations, hasPassword
        case avatarShape, avatarColor, badgeLayout, photoUrl, agentLine, agentConnected
        case respondFromM, dropShortEncounters
    }

    var displayName: String { name?.isEmpty == false ? name! : "Your name" }
    var badgeTags: [String] { tags ?? [] }
    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
    var layout: BadgeLayout { BadgeLayout(rawValue: badgeLayout ?? "") ?? .avatar }
    var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }

    /// Enough filled in for matching to work (drives the sleepy avatar).
    var isMatchable: Bool { name?.isEmpty == false && !(tags ?? []).isEmpty }
}

/// How the identity part of the badge is drawn.
enum BadgeLayout: String, CaseIterable, Identifiable {
    case avatar      // big name and the living avatar
    case photoText   // photo beside the name
    case photo       // full bleed photo, name over it
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .avatar: return "Avatar"
        case .photoText: return "Photo and text"
        case .photo: return "Photo"
        }
    }
}

/// Shape and color of someone's avatar, decoded from server strings.
struct AvatarStyle: Equatable {
    var shape: AvatarShapeKind
    var colorHex: String

    init(shape: String?, color: String?) {
        self.shape = AvatarShapeKind(serverValue: shape)
        self.colorHex = color ?? "#FF6C6E"
    }

    var color: Color { Color(hex: colorHex) }

    /// Stable per person seed so two avatars never blink in sync.
    static func seed(_ id: String) -> Int {
        id.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
    }
}

/// A photo on a profile, shown with hobbies.
struct Moment: Decodable, Identifiable {
    let id: String
    var caption: String?
    var url: String?
    var at: Double

    var imageURL: URL? { url.flatMap(URL.init(string:)) }
    var date: Date { Date(timeIntervalSince1970: at / 1000) }
}

/// Fields to change. Nil means "leave as is".
struct ProfilePatch {
    var name: String?
    var headline: String?
    var company: String?
    var location: String?
    var tags: [String]?
    var lookingFor: String?
    var offers: String?
    var hobbies: [String]?
    var appearance: String?
    var californiaMode: Bool?
    var recordConversations: Bool?
    var avatarShape: String?
    var avatarColor: String?
    var badgeLayout: String?
    var respondFromM: Double?
    var dropShortEncounters: Bool?
}
