import Foundation

/// In memory backend for SwiftUI previews and for running without Convex.
final class MockBackend: Backend {
    private var profile = UserProfile(
        id: "me", phone: "+15555550100", name: "Ethan", headline: "Building a networking badge",
        tags: ["Student", "Product designer", "Startup founder"], lookingFor: "iOS engineers",
        offers: "Design, multiagent systems", hobbies: ["Climbing"], appearance: nil,
        californiaMode: true, recordConversations: true, hasPassword: false
    )

    func signIn(phone: String, name: String?, password: String?) async throws -> String { "me" }
    func heartbeat(userId: String) async throws {}

    func me(userId: String) -> AsyncThrowingStream<UserProfile?, Error> { once(profile) }

    func updateProfile(userId: String, patch: ProfilePatch) async throws {
        if let v = patch.name { profile.name = v }
        if let v = patch.headline { profile.headline = v }
        if let v = patch.tags { profile.tags = v }
        if let v = patch.lookingFor { profile.lookingFor = v }
        if let v = patch.offers { profile.offers = v }
        if let v = patch.hobbies { profile.hobbies = v }
        if let v = patch.appearance { profile.appearance = v }
        if let v = patch.californiaMode { profile.californiaMode = v }
        if let v = patch.recordConversations { profile.recordConversations = v }
    }

    func badgeState(userId: String) -> AsyncThrowingStream<BadgeState, Error> {
        once(BadgeState(mode: .match, glow: 0.6, color: "#FF7A59", frontTag: "Product designer",
                        peerId: "p1", peerName: "Maya", conversationId: nil,
                        recordConversations: true, californiaMode: true))
    }

    func peers(userId: String) -> AsyncThrowingStream<[Peer], Error> { once([]) }
    func uploadToken(userId: String, peerId: String, token: String) async throws {}
    func reportDistance(userId: String, peerId: String, meters: Double) async throws {}
    func finishConversation(id: String, transcript: String?) async throws {}

    func people(userId: String) -> AsyncThrowingStream<[PersonSummary], Error> {
        once([])
    }

    func personDetail(userId: String, otherId: String) -> AsyncThrowingStream<PersonDetail?, Error> {
        once(nil)
    }

    func currentPerson(userId: String) -> AsyncThrowingStream<String?, Error> { once(nil) }

    private func once<T>(_ value: T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(value)
        }
    }
}
