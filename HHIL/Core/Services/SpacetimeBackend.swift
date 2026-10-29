import Foundation

enum BackendError: LocalizedError {
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .uploadFailed: return "The photo didn't upload. Try again."
        }
    }
}

/// Backend implementation on SpacetimeDB, over plain HTTP (there is no Swift SDK).
///
/// The module in `spacetime/` of the parent repo exposes HTTP routes:
///   POST {host}/v1/database/{db}/route/rpc     {"path": "users:me", "args": {...}} -> {"value": ...}
///   POST {host}/v1/database/{db}/route/upload  JPEG bytes -> {"storageId": "..."}
/// Function paths are the module's (`users:me`, `badge:state`, ...; see
/// spacetime/src/http.ts). Live queries are polling: each stream asks about
/// once a second and only yields when the answer changed.
final class SpacetimeBackend: Backend, @unchecked Sendable {
    private let routeBase: URL
    private let session: URLSession
    private let pollInterval: Duration = .seconds(1)

    /// `host` like https://maincloud.spacetimedb.com, `database` the published name.
    init?(host: String, database: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let db = database.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !db.isEmpty,
              let encoded = db.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(trimmedHost)/v1/database/\(encoded)/route"),
              url.scheme == "https" || url.scheme == "http"
        else { return nil }
        routeBase = url
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    // MARK: Account

    func signIn(phone: String, name: String?, password: String?) async throws -> String {
        try await call("users:signIn", ["phone": phone, "name": name, "password": password], String.self)
    }

    func heartbeat(userId: String) async throws {
        try await send("users:heartbeat", ["userId": userId])
    }

    func me(userId: String) -> AsyncThrowingStream<UserProfile?, Error> {
        poll("users:me", ["userId": userId], UserProfile?.self)
    }

    func updateProfile(userId: String, patch: ProfilePatch) async throws {
        let fields: [String: Any?] = [
            "name": patch.name,
            "headline": patch.headline,
            "company": patch.company,
            "location": patch.location,
            "avatarShape": patch.avatarShape,
            "avatarColor": patch.avatarColor,
            "badgeLayout": patch.badgeLayout,
            "tags": patch.tags,
            "lookingFor": patch.lookingFor,
            "offers": patch.offers,
            "hobbies": patch.hobbies,
            "appearance": patch.appearance,
            "californiaMode": patch.californiaMode,
            "recordConversations": patch.recordConversations,
            "respondFromM": patch.respondFromM,
            "dropShortEncounters": patch.dropShortEncounters,
        ]
        try await send("users:updateProfile", ["userId": userId, "patch": compact(fields)])
    }

    // MARK: Photos

    /// Photos are stored in the database itself: POST the bytes, get a storage id.
    func uploadImage(_ jpeg: Data) async throws -> String {
        var request = URLRequest(url: routeBase.appendingPathComponent("upload"))
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, from: jpeg)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BackendError.uploadFailed }
        struct Uploaded: Decodable { let storageId: String }
        return try JSONDecoder().decode(Uploaded.self, from: data).storageId
    }

    func setPhoto(userId: String, storageId: String?) async throws {
        try await send("users:setPhoto", ["userId": userId, "storageId": storageId])
    }

    func moments(userId: String) -> AsyncThrowingStream<[Moment], Error> {
        poll("users:moments", ["userId": userId], [Moment].self)
    }

    func addMoment(userId: String, storageId: String, caption: String?) async throws {
        try await send("users:addMoment", ["userId": userId, "storageId": storageId, "caption": caption])
    }

    func removeMoment(userId: String, momentId: String) async throws {
        try await send("users:removeMoment", ["userId": userId, "momentId": momentId])
    }

    // MARK: Badge and proximity

    func badgeState(userId: String) -> AsyncThrowingStream<BadgeState, Error> {
        poll("badge:state", ["userId": userId], BadgeState.self)
    }

    func peers(userId: String) -> AsyncThrowingStream<[Peer], Error> {
        poll("nearby:peers", ["userId": userId], [Peer].self)
    }

    func uploadToken(userId: String, peerId: String, token: String) async throws {
        try await send("nearby:uploadToken", ["userId": userId, "peerId": peerId, "token": token])
    }

    func reportDistance(userId: String, peerId: String, meters: Double, extended: Bool) async throws {
        try await send("nearby:reportDistance", ["userId": userId, "peerId": peerId, "meters": meters, "extended": extended])
    }

    func setRanging(userId: String, on: Bool) async throws {
        try await send("nearby:setRanging", ["userId": userId, "on": on])
    }

    func finishConversation(id: String, transcript: String?) async throws {
        try await send("conversations:finish", ["conversationId": id, "transcript": transcript])
    }

    func setRecordingConsent(userId: String, conversationId: String, agree: Bool) async throws {
        try await send("conversations:consent", ["userId": userId, "conversationId": conversationId, "agree": agree])
    }

    // MARK: People

    func people(userId: String) -> AsyncThrowingStream<[PersonSummary], Error> {
        poll("people:list", ["userId": userId], [PersonSummary].self)
    }

    func personDetail(userId: String, otherId: String) -> AsyncThrowingStream<PersonDetail?, Error> {
        poll("people:detail", ["userId": userId, "otherId": otherId], PersonDetail?.self)
    }

    func currentPerson(userId: String) -> AsyncThrowingStream<String?, Error> {
        poll("people:current", ["userId": userId], String?.self)
    }

    func markMet(userId: String, otherId: String) async throws {
        try await send("people:met", ["userId": userId, "otherId": otherId])
    }

    // MARK: Approximate location

    func reportLocation(userId: String, latitude: Double, longitude: Double, accuracy: Double) async throws {
        try await send("location:report", ["userId": userId, "lat": latitude, "lng": longitude, "accuracy": accuracy])
    }

    func clearLocation(userId: String) async throws {
        try await send("location:clear", ["userId": userId])
    }

    // MARK: Transport

    private struct Envelope<T: Decodable>: Decodable {
        let value: T
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    /// Drop nil values: the server treats a missing argument as "not given".
    private func compact(_ args: [String: Any?]) -> [String: Any] {
        args.compactMapValues { $0 }
    }

    /// The JSON request body for one call.
    private func body(_ path: String, _ args: [String: Any?]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["path": path, "args": compact(args)])
    }

    /// One RPC, returning the raw JSON body of a successful call.
    private func post(_ body: Data) async throws -> Data {
        var request = URLRequest(url: routeBase.appendingPathComponent("rpc"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
            throw SpacetimeError(status: status, message: message ?? "The server answered \(status).")
        }
        return data
    }

    private func call<T: Decodable>(_ path: String, _ args: [String: Any?], _ type: T.Type) async throws -> T {
        let data = try await post(body(path, args))
        return try JSONDecoder().decode(Envelope<T>.self, from: data).value
    }

    private func send(_ path: String, _ args: [String: Any?]) async throws {
        _ = try await post(body(path, args))
    }

    /// Poll a query about once a second; yield only when the answer changes.
    /// Bad arguments (4xx) end the stream (the caller decides what to do);
    /// network trouble is retried with a short backoff.
    private func poll<T: Decodable>(_ path: String, _ args: [String: Any?], _ type: T.Type) -> AsyncThrowingStream<T, Error> {
        let request: Data
        do { request = try body(path, args) } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let interval = pollInterval
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                var last: Data?
                var failures = 0
                while !Task.isCancelled {
                    guard let self else { break }
                    do {
                        let data = try await self.post(request)
                        failures = 0
                        if data != last {
                            last = data
                            continuation.yield(try JSONDecoder().decode(Envelope<T>.self, from: data).value)
                        }
                    } catch let error as SpacetimeError where error.isClientError {
                        continuation.finish(throwing: error)
                        return
                    } catch is CancellationError {
                        break
                    } catch let error as DecodingError {
                        continuation.finish(throwing: error)
                        return
                    } catch {
                        failures += 1
                        if failures == 5 { print("\(path) polling keeps failing:", error) }
                    }
                    try? await Task.sleep(for: failures == 0 ? interval : .seconds(min(5, failures)))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// An error answer from the SpacetimeDB module.
struct SpacetimeError: LocalizedError {
    let status: Int
    let message: String

    var isClientError: Bool { (400..<500).contains(status) }
    var errorDescription: String? { message }
}
