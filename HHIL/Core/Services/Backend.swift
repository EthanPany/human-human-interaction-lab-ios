import Foundation

/// Everything the app needs from the server. Views and stores only talk to
/// this protocol, so the Convex implementation can be swapped for the mock in
/// previews or when no backend is configured.
protocol Backend: AnyObject {
    // Account
    func signIn(phone: String, name: String?, password: String?) async throws -> String
    func heartbeat(userId: String) async throws
    func me(userId: String) -> AsyncThrowingStream<UserProfile?, Error>
    func updateProfile(userId: String, patch: ProfilePatch) async throws

    // Photos (JPEG data in, storage id out)
    func uploadImage(_ jpeg: Data) async throws -> String
    func setPhoto(userId: String, storageId: String?) async throws
    func moments(userId: String) -> AsyncThrowingStream<[Moment], Error>
    func addMoment(userId: String, storageId: String, caption: String?) async throws
    func removeMoment(userId: String, momentId: String) async throws

    // Badge and proximity
    func badgeState(userId: String) -> AsyncThrowingStream<BadgeState, Error>
    func peers(userId: String) -> AsyncThrowingStream<[Peer], Error>
    func uploadToken(userId: String, peerId: String, token: String) async throws
    func reportDistance(userId: String, peerId: String, meters: Double) async throws
    func finishConversation(id: String, transcript: String?) async throws

    // People (CRM)
    func people(userId: String) -> AsyncThrowingStream<[PersonSummary], Error>
    func personDetail(userId: String, otherId: String) -> AsyncThrowingStream<PersonDetail?, Error>
    func currentPerson(userId: String) -> AsyncThrowingStream<String?, Error>
}
