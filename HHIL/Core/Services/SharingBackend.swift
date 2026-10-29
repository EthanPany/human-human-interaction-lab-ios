import Foundation

/// Contact sharing and the profile photo (Phase 5). Part of `Backend`;
/// SpacetimeBackend+Sharing.swift and MockBackend+Sharing.swift implement it.
/// Server routes: spacetime/src/api/sharing.ts and profilePhoto.ts.
protocol SharingBackend: AnyObject {
    // Profile photo (square, People rows and pages; the badge keeps the jelly avatar)
    func setProfilePhoto(userId: String, storageId: String?) async throws

    // What I share
    func shareItems(userId: String) -> AsyncThrowingStream<[ShareItem], Error>
    @discardableResult
    func saveShareItem(userId: String, draft: ShareItemDraft) async throws -> String
    func removeShareItem(userId: String, itemId: String) async throws
    func reorderShareItems(userId: String, itemIds: [String]) async throws

    // Requests and answers
    /// `offer`: share my items (nil: my preselected ones). `ask`: ask for theirs.
    func requestShare(userId: String, otherId: String, offer: Bool, itemIds: [String]?) async throws
    /// Ask: `itemIds` is what I share (nil: preselected). Offer: accepting; `itemIds` shares mine back.
    func respondToShare(userId: String, requestId: String, approve: Bool, itemIds: [String]?) async throws
    func cancelShareRequest(userId: String, requestId: String) async throws
    /// Stop sharing these (nil: all) of mine with them.
    func revokeShare(userId: String, otherId: String, itemIds: [String]?) async throws
    /// Apple Watch handshake (Phase 6): one side's approval of a mutual share.
    func shareHandshake(userId: String, otherId: String, itemIds: [String]?) async throws -> HandshakeResult

    // Live reads
    func shareInbox(userId: String) -> AsyncThrowingStream<[ShareRequest], Error>
    func sharing(userId: String, otherId: String) -> AsyncThrowingStream<SharingWith, Error>
}
