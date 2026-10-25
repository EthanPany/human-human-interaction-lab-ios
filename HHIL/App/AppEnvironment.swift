import Foundation
import Observation

/// Builds and owns the app's services and stores. One instance per app.
@MainActor
@Observable
final class AppEnvironment {
    let backend: Backend
    let session: SessionStore
    let badge: BadgeStore
    let router = Router()
    let nearby: NearbyService
    let motion = MotionService()
    let usingMock: Bool
    /// The server in use (nil for the in memory mock).
    let provider: BackendProvider?
    /// The person you're with or met most recently (iPhone Duo opens to them).
    private(set) var currentPersonId: String?
    private var currentPersonTask: Task<Void, Never>?

    init(backend: Backend, usingMock: Bool, provider: BackendProvider? = nil) {
        self.backend = backend
        self.usingMock = usingMock
        self.provider = provider
        let recorder = ConversationRecorder()
        session = SessionStore(backend: backend)
        badge = BadgeStore(backend: backend, recorder: recorder)
        nearby = NearbyService(backend: backend)
    }

    /// The provider chosen in Settings when it is configured, otherwise the in memory mock.
    static func live() -> AppEnvironment {
        switch AppConfig.backendProvider {
        case .convex:
            if let url = AppConfig.convexURL {
                return AppEnvironment(backend: ConvexBackend(url: url), usingMock: false, provider: .convex)
            }
        case .spacetime:
            if let database = AppConfig.spacetimeDatabase,
               let backend = SpacetimeBackend(host: AppConfig.spacetimeHost, database: database) {
                return AppEnvironment(backend: backend, usingMock: false, provider: .spacetime)
            }
        }
        return AppEnvironment(backend: MockBackend(), usingMock: true)
    }

    static func preview() -> AppEnvironment {
        AppEnvironment(backend: MockBackend(), usingMock: true)
    }

    /// Start live services for the signed in user (and stop them on sign out).
    func userDidChange(_ userId: String?) {
        currentPersonTask?.cancel()
        if let userId {
            badge.start(userId: userId)
            nearby.start(userId: userId)
            currentPersonTask = Task { [backend] in
                do {
                    for try await id in backend.currentPerson(userId: userId) { self.currentPersonId = id }
                } catch {
                    print("current person stream ended:", error)
                }
            }
        } else {
            badge.stop()
            nearby.stop()
            currentPersonId = nil
        }
    }
}
