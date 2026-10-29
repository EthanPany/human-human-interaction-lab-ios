import Foundation

/// Everything the app needs from the server. Views and stores only talk to
/// this protocol, so SpacetimeBackend can be swapped for the mock in previews
/// and UI tests.
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
    /// `extended`: this pair's session runs extended UWB (about 50 m instead of 9 m).
    func reportDistance(userId: String, peerId: String, meters: Double, extended: Bool) async throws
    /// The badge is worn full screen (UWB on) or not; off drops my distances at once.
    func setRanging(userId: String, on: Bool) async throws
    func finishConversation(id: String, transcript: String?) async throws
    /// California mode: my answer to "record this conversation?" (recording needs both yeses).
    func setRecordingConsent(userId: String, conversationId: String, agree: Bool) async throws

    // People (CRM)
    func people(userId: String) -> AsyncThrowingStream<[PersonSummary], Error>
    func personDetail(userId: String, otherId: String) -> AsyncThrowingStream<PersonDetail?, Error>
    func currentPerson(userId: String) -> AsyncThrowingStream<String?, Error>
    /// We met in person (the badge's meet moment): they join my People list.
    func markMet(userId: String, otherId: String) async throws

    // Approximate location (Core/Location): gates heads up texts, expires on the server after 15 minutes
    func reportLocation(userId: String, latitude: Double, longitude: Double, accuracy: Double) async throws
    func clearLocation(userId: String) async throws
}

/// Only SpacetimeDB stores a coarse location; the others ignore it.
extension Backend {
    func reportLocation(userId: String, latitude: Double, longitude: Double, accuracy: Double) async throws {}
    func clearLocation(userId: String) async throws {}
}
