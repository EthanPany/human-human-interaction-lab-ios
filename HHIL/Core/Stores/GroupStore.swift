import Foundation
import Observation

/// My group encounters (three or more together), live, for the People list.
/// A group's own page streams its detail itself, like the person page.
@MainActor
@Observable
final class GroupStore {
    private(set) var encounters: [GroupEncounterSummary] = []

    private let backend: Backend
    private var task: Task<Void, Never>?

    init(backend: Backend) {
        self.backend = backend
    }

    func start(userId: String) {
        stop()
        task = Task { [backend] in
            do {
                for try await list in backend.groupEncounters(userId: userId) {
                    if list != self.encounters { self.encounters = list }
                }
            } catch {
                print("groups stream ended:", error)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        encounters = []
    }
}
