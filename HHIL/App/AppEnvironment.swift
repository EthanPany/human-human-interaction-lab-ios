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
    /// The person you're with or met most recently (iPhone Duo opens to them).
    private(set) var currentPersonId: String?
    private var currentPersonTask: Task<Void, Never>?

    init(backend: Backend, usingMock: Bool, start: SessionStore.Start = .restoreSaved) {
        self.backend = backend
        self.usingMock = usingMock
        let recorder = ConversationRecorder()
        session = SessionStore(backend: backend, start: start)
        badge = BadgeStore(backend: backend, recorder: recorder)
        nearby = NearbyService(backend: backend)
    }

    /// Convex when a URL is configured, otherwise the in memory mock.
    /// UI tests pass `-uiTestDemo` (mock, signed in as the demo user) or
    /// `-uiTestSignedOut` (mock, on the sign in screen).
    static func live() -> AppEnvironment {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-uiTestSignedOut") {
            return AppEnvironment(backend: MockBackend(), usingMock: true, start: .signedOut)
        }
        if arguments.contains("-uiTestDemo") {
            return AppEnvironment(backend: MockBackend(), usingMock: true, start: .signedIn(MockBackend.demoUserId))
        }
        if let url = AppConfig.convexURL {
            return AppEnvironment(backend: ConvexBackend(url: url), usingMock: false)
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
