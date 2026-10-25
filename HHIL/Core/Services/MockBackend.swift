import Foundation

/// In memory backend for SwiftUI previews and for running without Convex.
/// Live queries are real streams: edits made in the app show up right away.
final class MockBackend: Backend {
    private var profile = UserProfile(
        id: "me", phone: "+15555550100", name: "Ethan", headline: "Brand marketer", company: "Cal Hacks",
        location: "Berkeley, CA", tags: ["Student", "Product designer", "Startup founder"],
        lookingFor: "iOS engineers", offers: "Design, multiagent systems", hobbies: ["Climbing", "Film photos"],
        appearance: nil, californiaMode: true, recordConversations: true, hasPassword: false,
        avatarShape: "puzzle", avatarColor: "#FF6C6E", badgeLayout: "avatar", photoUrl: nil
    )
    private var profileWatchers: [UUID: AsyncThrowingStream<UserProfile?, Error>.Continuation] = [:]

    func signIn(phone: String, name: String?, password: String?) async throws -> String { "me" }
    func heartbeat(userId: String) async throws {}

    func me(userId: String) -> AsyncThrowingStream<UserProfile?, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            profileWatchers[id] = continuation
            continuation.yield(profile)
            continuation.onTermination = { [weak self] _ in self?.profileWatchers[id] = nil }
        }
    }

    func updateProfile(userId: String, patch: ProfilePatch) async throws {
        if let v = patch.name { profile.name = v }
        if let v = patch.headline { profile.headline = v }
        if let v = patch.company { profile.company = v }
        if let v = patch.location { profile.location = v }
        if let v = patch.tags { profile.tags = v }
        if let v = patch.lookingFor { profile.lookingFor = v }
        if let v = patch.offers { profile.offers = v }
        if let v = patch.hobbies { profile.hobbies = v }
        if let v = patch.appearance { profile.appearance = v }
        if let v = patch.californiaMode { profile.californiaMode = v }
        if let v = patch.recordConversations { profile.recordConversations = v }
        if let v = patch.avatarShape { profile.avatarShape = v }
        if let v = patch.avatarColor { profile.avatarColor = v }
        if let v = patch.badgeLayout { profile.badgeLayout = v }
        profileWatchers.values.forEach { $0.yield(profile) }
    }

    func uploadImage(_ jpeg: Data) async throws -> String { "mock-storage" }
    func setPhoto(userId: String, storageId: String?) async throws {}
    func moments(userId: String) -> AsyncThrowingStream<[Moment], Error> { once([]) }
    func addMoment(userId: String, storageId: String, caption: String?) async throws {}
    func removeMoment(userId: String, momentId: String) async throws {}

    /// Cycles idle -> match (approaching) -> talking -> connected so every
    /// badge state can be seen without a second phone.
    func badgeState(userId: String) -> AsyncThrowingStream<BadgeState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let steps: [(BadgeMode, Double)] = [(.idle, 0), (.match, 0.2), (.match, 0.5), (.match, 0.85), (.talking, 1), (.connected, 1)]
                while !Task.isCancelled {
                    for (mode, closeness) in steps {
                        continuation.yield(BadgeState(
                            mode: mode, glow: closeness, color: mode == .idle ? nil : "#87D9FB",
                            frontTag: mode == .idle ? nil : "Product designer",
                            peerId: mode == .idle ? nil : "p1", peerName: mode == .idle ? nil : "Maya",
                            peerAvatarShape: "blob", peerAvatarColor: "#3BB52D", closeness: closeness,
                            conversationId: nil, recordConversations: true, californiaMode: true
                        ))
                        try? await Task.sleep(for: .seconds(4))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func peers(userId: String) -> AsyncThrowingStream<[Peer], Error> { once([]) }
    func uploadToken(userId: String, peerId: String, token: String) async throws {}
    func reportDistance(userId: String, peerId: String, meters: Double) async throws {}
    func finishConversation(id: String, transcript: String?) async throws {}

    func people(userId: String) -> AsyncThrowingStream<[PersonSummary], Error> { once([]) }
    func personDetail(userId: String, otherId: String) -> AsyncThrowingStream<PersonDetail?, Error> { once(nil) }
    func currentPerson(userId: String) -> AsyncThrowingStream<String?, Error> { once(nil) }

    private func once<T>(_ value: T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in continuation.yield(value) }
    }
}
