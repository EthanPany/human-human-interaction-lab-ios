import Foundation
import Observation

/// Who is signed in, their live profile, and the "I'm here" heartbeat.
@MainActor
@Observable
final class SessionStore {
    private(set) var userId: String?
    private(set) var profile: UserProfile?
    var lastError: String?

    private let backend: Backend
    private var profileTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
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
            didSignIn(id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.userIdKey)
        profileTask?.cancel()
        heartbeatTask?.cancel()
        userId = nil
        profile = nil
    }

    func update(_ patch: ProfilePatch) async {
        guard let userId else { return }
        do { try await backend.updateProfile(userId: userId, patch: patch) }
        catch { lastError = error.localizedDescription }
    }

    private func didSignIn(_ id: String) {
        userId = id
        profileTask?.cancel()
        profileTask = Task { [backend] in
            do {
                for try await p in backend.me(userId: id) { self.profile = p }
            } catch {
                self.lastError = error.localizedDescription
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

extension String {
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
