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
    var conversationId: String?
    var recordConversations: Bool
    var californiaMode: Bool

    static let idle = BadgeState(
        mode: .idle, glow: 0, color: nil, frontTag: nil, peerId: nil, peerName: nil,
        conversationId: nil, recordConversations: true, californiaMode: true
    )

    init(mode: BadgeMode, glow: Double, color: String?, frontTag: String?, peerId: String?,
         peerName: String?, conversationId: String?, recordConversations: Bool, californiaMode: Bool) {
        self.mode = mode
        self._glow = ConvexFloat(wrappedValue: glow)
        self.color = color
        self.frontTag = frontTag
        self.peerId = peerId
        self.peerName = peerName
        self.conversationId = conversationId
        self.recordConversations = recordConversations
        self.californiaMode = californiaMode
    }
}
