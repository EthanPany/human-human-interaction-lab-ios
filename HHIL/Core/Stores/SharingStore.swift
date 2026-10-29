import Foundation
import Observation
import SwiftUI

/// My shareable items and the share requests waiting for me, live, plus the
/// actions on them. Per person state (`sharing:with`) is streamed by the
/// person page itself, like the person detail.
@MainActor
@Observable
final class SharingStore {
    private(set) var items: [ShareItem] = []
    private(set) var inbox: [ShareRequest] = []
    /// True while something is saving or uploading (drives spinners).
    private(set) var isBusy = false
    /// The last error, shown by whichever screen did the action.
    var lastError: String?

    private let backend: Backend
    private var userId: String?
    private var itemsTask: Task<Void, Never>?
    private var inboxTask: Task<Void, Never>?

    init(backend: Backend) {
        self.backend = backend
    }

    var defaultItemIds: [String] { items.filter(\.includeByDefault).map(\.id) }

    func start(userId: String) {
        stop()
        self.userId = userId
        itemsTask = Task { [backend] in
            do {
                for try await list in backend.shareItems(userId: userId) { self.items = list }
            } catch {
                print("share items stream ended:", error)
            }
        }
        inboxTask = Task { [backend] in
            var seen: Set<String>?
            do {
                for try await list in backend.shareInbox(userId: userId) {
                    // A card that arrives while the app is open: the soft chime of a match appearing
                    if let seen, list.contains(where: { !seen.contains($0.id) }) {
                        Feedback.shared.play(.matchAppears)
                    }
                    seen = (seen ?? []).union(list.map(\.id))
                    self.inbox = list
                }
            } catch {
                print("share inbox stream ended:", error)
            }
        }
    }

    func stop() {
        itemsTask?.cancel()
        inboxTask?.cancel()
        userId = nil
        items = []
        inbox = []
    }

    // MARK: Items

    /// Save a new or edited item; an image is uploaded first. True when saved.
    @discardableResult
    func save(_ draft: ShareItemDraft, image: Data? = nil) async -> Bool {
        guard let userId else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            var draft = draft
            if let image { draft.storageId = try await backend.uploadImage(image) }
            try await backend.saveShareItem(userId: userId, draft: draft)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            Feedback.shared.play(.error)
            return false
        }
    }

    func setDefault(_ item: ShareItem, _ on: Bool) async {
        await save(ShareItemDraft(id: item.id, kind: item.shareKind, label: item.label,
                                  value: item.value ?? "", includeByDefault: on))
    }

    func remove(_ item: ShareItem) async {
        await run { try await self.backend.removeShareItem(userId: $0, itemId: item.id) }
    }

    func move(from source: IndexSet, to destination: Int) async {
        var ids = items.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        items.move(fromOffsets: source, toOffset: destination)
        await run { try await self.backend.reorderShareItems(userId: $0, itemIds: ids) }
    }

    // MARK: Requests

    /// Share my items (nil: my preselected ones) with someone I met.
    @discardableResult
    func offer(to otherId: String, itemIds: [String]?) async -> Bool {
        await run { try await self.backend.requestShare(userId: $0, otherId: otherId, offer: true, itemIds: itemIds) }
    }

    @discardableResult
    func ask(_ otherId: String) async -> Bool {
        await run { try await self.backend.requestShare(userId: $0, otherId: otherId, offer: false, itemIds: nil) }
    }

    /// Approve (with what I share) or decline.
    @discardableResult
    func respond(_ request: ShareRequest, approve: Bool, itemIds: [String]? = nil) async -> Bool {
        inbox.removeAll { $0.id == request.id }
        let ok = await run {
            try await self.backend.respondToShare(userId: $0, requestId: request.id, approve: approve, itemIds: itemIds)
        }
        if ok && approve { Feedback.shared.play(.saved) }
        return ok
    }

    func cancel(_ request: ShareRequest) async {
        await run { try await self.backend.cancelShareRequest(userId: $0, requestId: request.id) }
    }

    func revoke(_ otherId: String, itemIds: [String]? = nil) async {
        await run { try await self.backend.revokeShare(userId: $0, otherId: otherId, itemIds: itemIds) }
    }

    @discardableResult
    private func run(_ action: @escaping (String) async throws -> Void) async -> Bool {
        guard let userId else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await action(userId)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            Feedback.shared.play(.error)
            return false
        }
    }
}
