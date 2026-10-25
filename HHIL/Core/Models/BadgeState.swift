import Foundation
import ConvexMobile

enum BadgeMode: String, Decodable {
    case idle, match, talking, connected
}

/// Live badge state from `badge:state`. Drives glow, color and the front tag.
struct BadgeState: Decodable {
    var mode: BadgeMode
    @ConvexFloat var glow: Double
    var color: String?
    var frontTag: String?
    var peerId: String?
    var peerName: String?
    var peerAvatarShape: String?
    var peerAvatarColor: String?
    @ConvexFloat var closeness: Double
    var conversationId: String?
    var recordConversations: Bool
    var californiaMode: Bool

    static let idle = BadgeState(
        mode: .idle, glow: 0, color: nil, frontTag: nil, peerId: nil, peerName: nil,
        peerAvatarShape: nil, peerAvatarColor: nil, closeness: 0,
        conversationId: nil, recordConversations: true, californiaMode: true
    )

    var peerAvatar: AvatarStyle? {
        peerId == nil ? nil : AvatarStyle(shape: peerAvatarShape, color: peerAvatarColor)
    }

    /// The two avatars have met: they share one frame.
    var hasMet: Bool { mode == .talking || mode == .connected }

    init(mode: BadgeMode, glow: Double, color: String?, frontTag: String?, peerId: String?,
         peerName: String?, peerAvatarShape: String?, peerAvatarColor: String?, closeness: Double,
         conversationId: String?, recordConversations: Bool, californiaMode: Bool) {
        self.mode = mode
        self._glow = ConvexFloat(wrappedValue: glow)
        self.color = color
        self.frontTag = frontTag
        self.peerId = peerId
        self.peerName = peerName
        self.peerAvatarShape = peerAvatarShape
        self.peerAvatarColor = peerAvatarColor
        self._closeness = ConvexFloat(wrappedValue: closeness)
        self.conversationId = conversationId
        self.recordConversations = recordConversations
        self.californiaMode = californiaMode
    }
}
