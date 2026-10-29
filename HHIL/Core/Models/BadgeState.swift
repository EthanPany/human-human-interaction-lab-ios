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
    /// The pair's distance merged from both phones (either side seeing the
    /// other is enough), how old it is, and where it came from: "uwb", or "ble"
    /// for a coarse Bluetooth estimate.
    var meters: Double? = nil
    var distanceAgeMs: Double? = nil
    var distanceSource: String? = nil
    /// Bluetooth alone says we are together (UWB had nothing for a while).
    var estimated: Bool? = nil
    /// Three or more of us together right now: one shared encounter (see Group.swift).
    var group: Bool? = nil
    /// Everyone else in my encounter right now, first joined first (pairs too; nil from older servers).
    var members: [BadgeMember]? = nil
    /// This phone records the encounter (a group records on one phone; a pair on both).
    var isRecorder: Bool? = nil

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

    /// Recording may start on this phone (in a group, only on the one recording it).
    var mayRecord: Bool { (recordingAllowed ?? !needsConsent) && (isRecorder ?? true) }

    /// The others on the badge while together: the server's members, or the one peer.
    var togetherMembers: [BadgeMember] {
        if let members, !members.isEmpty { return members }
        guard mode == .talking, let peerId else { return [] }
        return [BadgeMember(id: peerId, name: peerName, avatarShape: peerAvatarShape, avatarColor: peerAvatarColor,
                            matched: matched ?? true, color: color, joinedAt: 0)]
    }

    /// Three or more of us (me and at least two others).
    var isGroup: Bool { group ?? ((members?.count ?? 0) >= 2) }

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

/// A soft glow on one side edge of the badge for a match in the area, shown
/// when two or more matches are around at once (BadgeStore picks up to two,
/// one per side, and keeps each person on their side).
struct EdgeGlow: Equatable, Identifiable {
    enum Side: Hashable {
        case leading, trailing
        var opposite: Side { self == .leading ? .trailing : .leading }
    }
    /// The peer's user id.
    let id: String
    var side: Side
    /// Their avatar color (or the pair color), "#RRGGBB".
    var colorHex: String
    /// 0...1 from their distance (faint when only Bluetooth hears them).
    var intensity: Double
}
