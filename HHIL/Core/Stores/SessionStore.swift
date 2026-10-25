import Foundation
import Observation

/// Who is signed in, their live profile, and the "I'm here" heartbeat.
@MainActor
@Observable
final class SessionStore {
    private(set) var userId: String?
    private(set) var profile: UserProfile?
    private(set) var moments: [Moment] = []
    /// True while a photo is uploading (drives a spinner).
    private(set) var isUploading = false
    var lastError: String?

    private let backend: Backend
    private var profileTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var momentsTask: Task<Void, Never>?
    private static let userIdKey = "userId"

    init(backend: Backend) {
        self.backend = backend
        if let saved = UserDefaults.standard.string(forKey: Self.userIdKey) {
            didSignIn(saved)
        }
    }

    var isSignedIn: Bool { userId != nil }

    /// The phone number is the account. Password is optional.
    func signIn(phone: String, name: String?, password: String?) async {
        do {
            let id = try await backend.signIn(
                phone: phone,
                name: name?.nilIfBlank,
                password: password?.nilIfBlank
            )
            UserDefaults.standard.set(id, forKey: Self.userIdKey)
            lastError = nil
            didSignIn(id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.userIdKey)
        profileTask?.cancel()
        heartbeatTask?.cancel()
        momentsTask?.cancel()
        userId = nil
        profile = nil
        moments = []
    }

    func update(_ patch: ProfilePatch) async {
        guard let userId else { return }
        do { try await backend.updateProfile(userId: userId, patch: patch) }
        catch { lastError = error.localizedDescription }
    }

    // MARK: Photos

    /// Badge photo. Pass nil to remove it.
    func setPhoto(_ jpeg: Data?) async {
        guard let userId else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let storageId = try await jpeg.asyncMap { try await backend.uploadImage($0) }
            try await backend.setPhoto(userId: userId, storageId: storageId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addMoment(_ jpeg: Data, caption: String?) async {
        guard let userId else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            let storageId = try await backend.uploadImage(jpeg)
            try await backend.addMoment(userId: userId, storageId: storageId, caption: caption?.nilIfBlank)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func removeMoment(_ moment: Moment) async {
        guard let userId else { return }
        do { try await backend.removeMoment(userId: userId, momentId: moment.id) }
        catch { lastError = error.localizedDescription }
    }

    private func didSignIn(_ id: String) {
        userId = id
        profileTask?.cancel()
        profileTask = Task { [backend] in
            do {
                for try await p in backend.me(userId: id) {
                    // The account is gone (database reset, other deployment): start over.
                    guard let p else { self.signOut(); return }
                    self.profile = p
                }
            } catch {
                // An id from another deployment fails argument validation: start
                // over. Anything else (network, server hiccup) keeps you signed in.
                print("profile stream failed:", error)
                if "\(error)".localizedCaseInsensitiveContains("validat") {
                    self.signOut()
                } else {
                    self.lastError = error.localizedDescription
                }
            }
        }
        momentsTask?.cancel()
        momentsTask = Task { [backend] in
            do {
                for try await list in backend.moments(userId: id) { self.moments = list }
            } catch {
                print("moments stream ended:", error)
            }
        }
        heartbeatTask?.cancel()
        heartbeatTask = Task { [backend] in
            while !Task.isCancelled {
                try? await backend.heartbeat(userId: id)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        switch self {
        case .some(let value): return try await transform(value)
        case .none: return nil
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
