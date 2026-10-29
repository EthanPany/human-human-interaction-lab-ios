import Foundation

/// Group encounters (three or more together). Part of `Backend`; SpacetimeBackend
/// and MockBackend+Groups.swift implement it. Server: spacetime/src/api/groups.ts.
protocol GroupBackend: AnyObject {
    /// My group encounters, newest first (the People list's group rows).
    func groupEncounters(userId: String) -> AsyncThrowingStream<[GroupEncounterSummary], Error>
    /// One group encounter's page (nil: not mine, or dropped for me).
    func groupEncounter(userId: String, encounterId: String) -> AsyncThrowingStream<GroupEncounterDetail?, Error>
    /// A phone stopped recording: upload what it heard. `startedAt`: when that recording started.
    /// `leaving` false keeps me in the encounter (another phone records the group now, or recording paused).
    func uploadTranscript(userId: String, conversationId: String, transcript: String?, startedAt: Date?, leaving: Bool) async throws
}
