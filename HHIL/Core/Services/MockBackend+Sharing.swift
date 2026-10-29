import Foundation

/// In memory sharing for previews and UI tests: my items, an offer from
/// Daniel waiting in the inbox, Maya already sharing with me, and the other
/// side answering my requests a few seconds later (so every state shows).
final class MockSharingState {
    var items: [ShareItem] = [
        ShareItem(id: "i1", kind: "linkedin", label: "LinkedIn", value: "ethanpan",
                  url: ShareKind.linkedin.link(for: "ethanpan")?.absoluteString, photoUrl: nil, includeByDefault: true),
        ShareItem(id: "i2", kind: "github", label: "GitHub", value: "EthanPany",
                  url: ShareKind.github.link(for: "EthanPany")?.absoluteString, photoUrl: nil, includeByDefault: true),
        ShareItem(id: "i3", kind: "email", label: "Email", value: "ethan@example.com",
                  url: "mailto:ethan@example.com", photoUrl: nil, includeByDefault: false),
    ]
    /// Pending requests, by id.
    var requests: [String: (sender: String, recipient: String, request: ShareRequest)] = [:]
    /// owner|viewer to item ids.
    var grants: [String: [String]] = [:]
    /// Other people's items (they can share these with me).
    var theirItems: [String: [ShareItem]] = [
        "p1": [
            ShareItem(id: "m1", kind: "linkedin", label: "LinkedIn", value: "maya-designs",
                      url: "https://www.linkedin.com/in/maya-designs", photoUrl: nil, includeByDefault: true),
            ShareItem(id: "m2", kind: "website", label: "Portfolio", value: "maya.design",
                      url: "https://maya.design", photoUrl: nil, includeByDefault: true),
        ],
        "p2": [
            ShareItem(id: "d1", kind: "x", label: "X", value: "@danielevals",
                      url: "https://x.com/danielevals", photoUrl: nil, includeByDefault: true),
            ShareItem(id: "d2", kind: "email", label: "Email", value: "daniel@example.com",
                      url: "mailto:daniel@example.com", photoUrl: nil, includeByDefault: true),
        ],
    ]

    var itemWatchers: [UUID: AsyncThrowingStream<[ShareItem], Error>.Continuation] = [:]
    var inboxWatchers: [UUID: AsyncThrowingStream<[ShareRequest], Error>.Continuation] = [:]
    var withWatchers: [UUID: (otherId: String, continuation: AsyncThrowingStream<SharingWith, Error>.Continuation)] = [:]

    init() {
        grants["p1|me"] = ["m1", "m2"]
        let offer = ShareRequest(
            id: "r-daniel", kind: "offer", createdAt: Date().timeIntervalSince1970 * 1000 - 5 * 60_000, source: "app",
            items: [SharePreviewItem(id: "d1", kind: "x", label: "X"), SharePreviewItem(id: "d2", kind: "email", label: "Email")],
            from: SharePerson(id: "p2", name: "Daniel Okafor", headline: "ML engineer", company: "Anthropic",
                              avatarShape: "flower", avatarColor: "#EB8FFF", profilePhotoUrl: nil)
        )
        requests[offer.id] = ("p2", MockBackend.demoUserId, offer)
    }

    func inbox(for userId: String) -> [ShareRequest] {
        requests.values.filter { $0.recipient == userId }.map(\.request).sorted { $0.createdAt > $1.createdAt }
    }

    func with(_ userId: String, _ otherId: String) -> SharingWith {
        let theirIds = grants["\(otherId)|\(userId)"] ?? []
        let incoming = requests.values.first { $0.sender == otherId && $0.recipient == userId }?.request
        let outgoing = requests.values.first { $0.sender == userId && $0.recipient == otherId }?.request
        return SharingWith(
            theirs: (theirItems[otherId] ?? []).filter { theirIds.contains($0.id) },
            sharedWithMeAt: theirIds.isEmpty ? nil : Date().timeIntervalSince1970 * 1000,
            mine: (grants["\(userId)|\(otherId)"] ?? []).filter { id in items.contains { $0.id == id } },
            sharedByMeAt: nil,
            incoming: incoming,
            outgoing: outgoing
        )
    }

    func publish(_ userId: String) {
        itemWatchers.values.forEach { $0.yield(items) }
        inboxWatchers.values.forEach { $0.yield(inbox(for: userId)) }
        withWatchers.values.forEach { $0.continuation.yield(with(userId, $0.otherId)) }
    }

    func grant(owner: String, viewer: String, ids: [String]) {
        let key = "\(owner)|\(viewer)"
        grants[key] = Array(Set((grants[key] ?? []) + ids))
    }
}

extension MockBackend {
    private var me: String { MockBackend.demoUserId }

    func shareItems(userId: String) -> AsyncThrowingStream<[ShareItem], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            sharingState.itemWatchers[id] = continuation
            continuation.yield(sharingState.items)
            continuation.onTermination = { [weak self] _ in self?.sharingState.itemWatchers[id] = nil }
        }
    }

    @discardableResult
    func saveShareItem(userId: String, draft: ShareItemDraft) async throws -> String {
        let s = sharingState
        let id = draft.id ?? "i-\(UUID().uuidString)"
        let old = s.items.first { $0.id == id }
        let value = draft.value.nilIfBlank
        if draft.kind != .image && value == nil {
            throw SpacetimeError(status: 400, message: "Add your \(draft.kind.displayName) first.")
        }
        let photo = draft.kind == .image ? (mockURL(draft.storageId) ?? old?.photoUrl) : nil
        if draft.kind == .image && photo == nil {
            throw SpacetimeError(status: 400, message: "Pick an image to share.")
        }
        let item = ShareItem(
            id: id, kind: draft.kind.rawValue,
            label: draft.label.nilIfBlank ?? draft.kind.displayName,
            value: draft.kind == .image ? nil : value,
            url: draft.kind.link(for: value)?.absoluteString,
            photoUrl: photo, includeByDefault: draft.includeByDefault
        )
        if let index = s.items.firstIndex(where: { $0.id == id }) { s.items[index] = item } else { s.items.append(item) }
        s.publish(me)
        return id
    }

    func removeShareItem(userId: String, itemId: String) async throws {
        sharingState.items.removeAll { $0.id == itemId }
        sharingState.publish(me)
    }

    func reorderShareItems(userId: String, itemIds: [String]) async throws {
        let s = sharingState
        s.items.sort { (itemIds.firstIndex(of: $0.id) ?? .max) < (itemIds.firstIndex(of: $1.id) ?? .max) }
        s.publish(me)
    }

    /// The other person answers yes about 3 seconds later.
    func requestShare(userId: String, otherId: String, offer: Bool, itemIds: [String]?) async throws {
        let s = sharingState
        let mine = itemIds ?? s.items.filter(\.includeByDefault).map(\.id)
        if offer && mine.isEmpty { throw SpacetimeError(status: 400, message: "Add what you share in Settings first.") }
        let requestId = "r-\(UUID().uuidString)"
        let request = ShareRequest(id: requestId, kind: offer ? "offer" : "ask", createdAt: Date().timeIntervalSince1970 * 1000,
                                   source: "app", items: [], from: nil)
        s.requests[requestId] = (userId, otherId, request)
        s.publish(me)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.sharingState.requests.removeValue(forKey: requestId) != nil else { return }
            if offer {
                self.sharingState.grant(owner: userId, viewer: otherId, ids: mine)
            } else {
                let theirs = (self.sharingState.theirItems[otherId] ?? [
                    ShareItem(id: "\(otherId)-li", kind: "linkedin", label: "LinkedIn", value: otherId,
                              url: ShareKind.linkedin.link(for: otherId)?.absoluteString, photoUrl: nil, includeByDefault: true),
                ])
                self.sharingState.theirItems[otherId] = theirs
                self.sharingState.grant(owner: otherId, viewer: userId, ids: theirs.map(\.id))
            }
            self.sharingState.publish(self.me)
        }
    }

    func respondToShare(userId: String, requestId: String, approve: Bool, itemIds: [String]?) async throws {
        let s = sharingState
        guard let r = s.requests.removeValue(forKey: requestId) else { return }
        if approve {
            if r.request.isOffer {
                s.grant(owner: r.sender, viewer: userId, ids: r.request.items.map(\.id))
                if let back = itemIds, !back.isEmpty { s.grant(owner: userId, viewer: r.sender, ids: back) }
            } else {
                s.grant(owner: userId, viewer: r.sender, ids: itemIds ?? s.items.filter(\.includeByDefault).map(\.id))
            }
        }
        s.publish(me)
    }

    func cancelShareRequest(userId: String, requestId: String) async throws {
        sharingState.requests[requestId] = nil
        sharingState.publish(me)
    }

    func revokeShare(userId: String, otherId: String, itemIds: [String]?) async throws {
        let key = "\(userId)|\(otherId)"
        if let drop = itemIds {
            sharingState.grants[key] = (sharingState.grants[key] ?? []).filter { !drop.contains($0) }
        } else {
            sharingState.grants[key] = nil
        }
        sharingState.publish(me)
    }

    /// The mock's other side has always approved already: complete at once.
    func shareHandshake(userId: String, otherId: String, itemIds: [String]?) async throws -> HandshakeResult {
        let s = sharingState
        let mine = itemIds ?? s.items.filter(\.includeByDefault).map(\.id)
        let theirs = (s.theirItems[otherId] ?? []).filter(\.includeByDefault).map(\.id)
        s.grant(owner: userId, viewer: otherId, ids: mine)
        s.grant(owner: otherId, viewer: userId, ids: theirs)
        s.publish(me)
        return HandshakeResult(status: "complete", requestId: "handshake", expiresAt: nil,
                               sharedByMe: mine.count, sharedWithMe: theirs.count)
    }

    func shareInbox(userId: String) -> AsyncThrowingStream<[ShareRequest], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            sharingState.inboxWatchers[id] = continuation
            continuation.yield(sharingState.inbox(for: userId))
            continuation.onTermination = { [weak self] _ in self?.sharingState.inboxWatchers[id] = nil }
        }
    }

    func sharing(userId: String, otherId: String) -> AsyncThrowingStream<SharingWith, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            sharingState.withWatchers[id] = (otherId, continuation)
            continuation.yield(sharingState.with(userId, otherId))
            continuation.onTermination = { [weak self] _ in self?.sharingState.withWatchers[id] = nil }
        }
    }
}
