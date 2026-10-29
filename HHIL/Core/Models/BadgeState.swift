import Foundation

enum BadgeMode: String, Decodable {
    case idle, match, talking, connected
}

/// Live badge state from `badge:state`. Drives glow, color and the front tag.
///
/// Two kinds of peer show up: a match within the pair's respond range
/// (`matched`: tint, glow and approach cues), or anyone I'm together with
/// (talking, match or not: the avatars join and recording can start, but a
/// non match gets no tint).
struct BadgeState: Decodable {
    var mode: BadgeMode
    var glow: Double
    var color: String?
    var frontTag: String?
    /// 1 to 3 short topics printed big under my name (see backend badge.ts).
    var keywords: [String]?
    var peerId: String?
    var peerName: String?
    var peerAvatarShape: String?
    var peerAvatarColor: String?
    var closeness: Double
    var conversationId: String?
    var recordConversations: Bool
    var californiaMode: Bool
    /// The peer is a match (nil from servers before encounters: every peer was one).
    var matched: Bool?
    /// Where this pair's badges start reacting, meters (the smaller "Respond from").
    var respondRangeM: Double?
    /// Either of us has California mode on: recording waits for both yeses.
    var consentRequired: Bool?
    var myConsent: Bool?
    var peerConsent: Bool?
    /// This phone may record now (both agreed, or no consent needed).
    var recordingAllowed: Bool?

    static let idle = BadgeState(
        mode: .idle, glow: 0, color: nil, frontTag: nil, peerId: nil, peerName: nil,
        peerAvatarShape: nil, peerAvatarColor: nil, closeness: 0,
        conversationId: nil, recordConversations: true, californiaMode: false
    )

    var peerAvatar: AvatarStyle? {
        peerId == nil ? nil : AvatarStyle(shape: peerAvatarShape, color: peerAvatarColor)
    }

    /// A match is near or with me: tint, glow and approach cues apply.
    var isMatch: Bool { mode != .idle && (matched ?? true) }

    /// Recording needs both people's yes (California mode on either side).
    var needsConsent: Bool { consentRequired ?? californiaMode }

    /// Recording may start on this phone.
    var mayRecord: Bool { recordingAllowed ?? !needsConsent }

    init(mode: BadgeMode, glow: Double, color: String?, frontTag: String?, peerId: String?,
         peerName: String?, peerAvatarShape: String?, peerAvatarColor: String?, closeness: Double,
         conversationId: String?, recordConversations: Bool, californiaMode: Bool, keywords: [String]? = nil,
         matched: Bool? = nil, respondRangeM: Double? = nil, consentRequired: Bool? = nil,
         myConsent: Bool? = nil, peerConsent: Bool? = nil, recordingAllowed: Bool? = nil) {
        self.mode = mode
        self.glow = glow
        self.color = color
        self.frontTag = frontTag
        self.keywords = keywords
        self.peerId = peerId
        self.peerName = peerName
        self.peerAvatarShape = peerAvatarShape
        self.peerAvatarColor = peerAvatarColor
        self.closeness = closeness
        self.conversationId = conversationId
        self.recordConversations = recordConversations
        self.californiaMode = californiaMode
        self.matched = matched
        self.respondRangeM = respondRangeM
        self.consentRequired = consentRequired
        self.myConsent = myConsent
        self.peerConsent = peerConsent
        self.recordingAllowed = recordingAllowed
    }
}
