import Foundation

/// What kind of thing someone shares (Settings > What I share). Raw values
/// match the server's `share_items.kind`.
enum ShareKind: String, CaseIterable, Identifiable, Codable {
    case linkedin, website, github, x, instagram, email, phone, link, image

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linkedin: return "LinkedIn"
        case .website: return "Website"
        case .github: return "GitHub"
        case .x: return "X"
        case .instagram: return "Instagram"
        case .email: return "Email"
        case .phone: return "Phone"
        case .link: return "Custom link"
        case .image: return "Image or QR code"
        }
    }

    /// SF Symbol for rows and chips (no brand logos).
    var systemImage: String {
        switch self {
        case .linkedin: return "person.crop.rectangle"
        case .website: return "globe"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .x: return "bubble.left"
        case .instagram: return "camera"
        case .email: return "envelope"
        case .phone: return "phone"
        case .link: return "link"
        case .image: return "qrcode"
        }
    }

    /// The hint in the value field.
    var placeholder: String {
        switch self {
        case .linkedin: return "linkedin.com/in/you or your handle"
        case .website: return "yourname.com"
        case .github: return "Your GitHub username"
        case .x: return "@handle"
        case .instagram: return "@handle"
        case .email: return "you@example.com"
        case .phone: return "+1 555 555 0100"
        case .link: return "https://"
        case .image: return ""
        }
    }

    /// Unknown kinds from a newer server show as a plain link.
    init(serverValue: String) { self = ShareKind(rawValue: serverValue) ?? .link }

    /// The link a value opens (the server sends `url` too; the mock uses this).
    func link(for value: String?) -> URL? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        let handle = v.hasPrefix("@") ? String(v.drop(while: { $0 == "@" })) : v
        let looksLikeURL = v.lowercased().hasPrefix("http") || v.lowercased().hasPrefix("www.") || v.contains("/")
        func web(_ s: String) -> URL? { URL(string: s.lowercased().hasPrefix("http") ? s : "https://\(s)") }
        let escaped = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
        switch self {
        case .linkedin: return looksLikeURL ? web(v) : URL(string: "https://www.linkedin.com/in/\(escaped)")
        case .github: return looksLikeURL ? web(v) : URL(string: "https://github.com/\(escaped)")
        case .x: return looksLikeURL ? web(v) : URL(string: "https://x.com/\(escaped)")
        case .instagram: return looksLikeURL ? web(v) : URL(string: "https://www.instagram.com/\(escaped)")
        case .email: return URL(string: "mailto:\(v)")
        case .phone: return URL(string: "tel:\(v.filter { $0.isNumber || $0 == "+" })")
        case .website, .link: return web(v)
        case .image: return nil
        }
    }
}

/// One thing I can share, or one someone shared with me.
struct ShareItem: Decodable, Identifiable, Equatable {
    let id: String
    var kind: String
    var label: String
    var value: String?
    var url: String?
    var photoUrl: String?
    var includeByDefault: Bool

    var shareKind: ShareKind { ShareKind(serverValue: kind) }
    var linkURL: URL? { url.flatMap(URL.init(string:)) }
    var photoURL: URL? { photoUrl.flatMap(URL.init(string:)) }
    var isImage: Bool { shareKind == .image }
}

/// A new or edited item, as sent to `sharing:saveItem`.
struct ShareItemDraft {
    var id: String?
    var kind: ShareKind
    var label: String = ""
    var value: String = ""
    /// A new image upload (images only).
    var storageId: String?
    var includeByDefault = true
}

/// An offered item before it is accepted: what it is, not its value.
struct SharePreviewItem: Decodable, Identifiable, Equatable {
    let id: String
    var kind: String
    var label: String

    var shareKind: ShareKind { ShareKind(serverValue: kind) }
}

/// Who sent a request.
struct SharePerson: Decodable, Equatable {
    let id: String
    var name: String?
    var headline: String?
    var company: String?
    var avatarShape: String?
    var avatarColor: String?
    var profilePhotoUrl: String?

    var displayName: String { name?.nilIfBlank ?? "Someone" }
    var avatar: AvatarStyle { AvatarStyle(shape: avatarShape, color: avatarColor) }
    var profilePhotoURL: URL? { profilePhotoUrl.flatMap(URL.init(string:)) }
}

/// A request waiting for an answer: they offer theirs, or ask for mine.
struct ShareRequest: Decodable, Identifiable, Equatable {
    let id: String
    var kind: String
    var createdAt: Double
    var source: String?
    /// Offers: what they would share (names only until accepted).
    var items: [SharePreviewItem]
    /// Inbox only: who it is from.
    var from: SharePerson?

    var isOffer: Bool { kind == "offer" }
    var createdDate: Date { Date(timeIntervalSince1970: createdAt / 1000) }
}

/// What two people share with each other (`sharing:with`).
struct SharingWith: Decodable, Equatable {
    /// Their items I can see (live).
    var theirs: [ShareItem]
    var sharedWithMeAt: Double?
    /// Which of my items they can see.
    var mine: [String]
    var sharedByMeAt: Double?
    /// They offered or asked; waiting for me.
    var incoming: ShareRequest?
    /// I offered or asked; waiting for them.
    var outgoing: ShareRequest?
    var lastDeclinedAt: Double?

    static let empty = SharingWith(theirs: [], mine: [])
}

/// `sharing:handshake` (Apple Watch, Phase 6).
struct HandshakeResult: Decodable, Equatable {
    /// "waiting" (the other person has not approved yet) or "complete".
    var status: String
    var requestId: String
    var expiresAt: Double?
    var sharedByMe: Int?
    var sharedWithMe: Int?
}
