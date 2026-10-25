import Foundation

/// The signed in person's profile. Every field is optional because people can
/// fill it by hand or let the text agent collect it over time.
struct UserProfile: Decodable, Identifiable {
    let id: String
    var phone: String
    var name: String?
    var headline: String?
    var tags: [String]?
    var lookingFor: String?
    var offers: String?
    var hobbies: [String]?
    var appearance: String?
    var californiaMode: Bool?
    var recordConversations: Bool?
    var hasPassword: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case phone, name, headline, tags, lookingFor, offers, hobbies, appearance
        case californiaMode, recordConversations, hasPassword
    }

    var displayName: String { name?.isEmpty == false ? name! : "Your name" }
    var badgeTags: [String] { tags ?? [] }
}

/// Fields to change. Nil means "leave as is".
struct ProfilePatch {
    var name: String?
    var headline: String?
    var tags: [String]?
    var lookingFor: String?
    var offers: String?
    var hobbies: [String]?
    var appearance: String?
    var californiaMode: Bool?
    var recordConversations: Bool?
}
