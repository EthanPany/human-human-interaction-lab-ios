import Foundation
import Combine
import ConvexMobile

/// Backend implementation on Convex. Function names match backend/convex/*.ts.
final class ConvexBackend: Backend {
    private let client: ConvexClient

    init(url: String) {
        client = ConvexClient(deploymentUrl: url)
    }

    // MARK: Account

    func signIn(phone: String, name: String?, password: String?) async throws -> String {
        try await client.mutation("users:signIn", with: [
            "phone": phone,
            "name": name,
            "password": password,
        ])
    }

    func heartbeat(userId: String) async throws {
        let _: String? = try await client.mutation("users:heartbeat", with: ["userId": userId])
    }

    func me(userId: String) -> AsyncThrowingStream<UserProfile?, Error> {
        stream("users:me", ["userId": userId], UserProfile?.self)
    }

    func updateProfile(userId: String, patch: ProfilePatch) async throws {
        var fields: [String: ConvexEncodable?] = [:]
        if let v = patch.name { fields["name"] = v }
        if let v = patch.headline { fields["headline"] = v }
        if let v = patch.tags { fields["tags"] = v }
        if let v = patch.lookingFor { fields["lookingFor"] = v }
        if let v = patch.offers { fields["offers"] = v }
        if let v = patch.hobbies { fields["hobbies"] = v }
        if let v = patch.appearance { fields["appearance"] = v }
        if let v = patch.californiaMode { fields["californiaMode"] = v }
        if let v = patch.recordConversations { fields["recordConversations"] = v }
        let _: String? = try await client.mutation("users:updateProfile", with: [
            "userId": userId,
            "patch": fields,
        ])
    }

    // MARK: Badge and proximity

    func badgeState(userId: String) -> AsyncThrowingStream<BadgeState, Error> {
        stream("badge:state", ["userId": userId], BadgeState.self)
    }

    func peers(userId: String) -> AsyncThrowingStream<[Peer], Error> {
        stream("nearby:peers", ["userId": userId], [Peer].self)
    }

    func uploadToken(userId: String, peerId: String, token: String) async throws {
        let _: String? = try await client.mutation("nearby:uploadToken", with: [
            "userId": userId, "peerId": peerId, "token": token,
        ])
    }

    func reportDistance(userId: String, peerId: String, meters: Double) async throws {
        let _: String? = try await client.mutation("nearby:reportDistance", with: [
            "userId": userId, "peerId": peerId, "meters": meters,
        ])
    }

    func finishConversation(id: String, transcript: String?) async throws {
        let _: String? = try await client.mutation("conversations:finish", with: [
            "conversationId": id, "transcript": transcript,
        ])
    }

    // MARK: People

    func people(userId: String) -> AsyncThrowingStream<[PersonSummary], Error> {
        stream("people:list", ["userId": userId], [PersonSummary].self)
    }

    func personDetail(userId: String, otherId: String) -> AsyncThrowingStream<PersonDetail?, Error> {
        stream("people:detail", ["userId": userId, "otherId": otherId], PersonDetail?.self)
    }

    func currentPerson(userId: String) -> AsyncThrowingStream<String?, Error> {
        stream("people:current", ["userId": userId], String?.self)
    }

    // MARK: Helpers

    /// Bridge a Convex live query (Combine) to an AsyncThrowingStream.
    private func stream<T: Decodable>(
        _ name: String,
        _ args: [String: ConvexEncodable?],
        _ type: T.Type
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let cancellable = client
                .subscribe(to: name, with: args, yielding: type)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            continuation.finish(throwing: error)
                        } else {
                            continuation.finish()
                        }
                    },
                    receiveValue: { value in continuation.yield(value) }
                )
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
