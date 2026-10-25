import Foundation

/// Debug only demo reel mode (`-demoReel`, used by HHILUITests/DemoReelTests to
/// record the demo video): a scripted approach, a faked recording, more people.
/// Always off in release builds.
enum DemoReel {
    static var isOn: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demoReel")
        #else
        false
        #endif
    }
    /// Seconds the badge stays idle before the scripted match starts approaching
    /// (`-demoApproachDelay 6`; a large number keeps it idle).
    static var approachDelay: Double {
        let v = UserDefaults.standard.double(forKey: "demoApproachDelay")
        return v > 0 ? v : 6
    }
}

/// In memory backend for SwiftUI previews and for running without Convex.
/// Live queries are real streams: edits made in the app show up right away.
final class MockBackend: Backend {
    static let demoUserId = "me"

    private var profile = UserProfile(
        id: demoUserId, phone: "+15555550100", name: "Ethan", headline: "Brand marketer", company: "Cal Hacks",
        location: "Berkeley, CA", tags: ["Student", "Product designer", "Startup founder"],
        lookingFor: "iOS engineers", offers: "Design, multiagent systems", hobbies: ["Climbing", "Film photos"],
        appearance: nil, californiaMode: false, recordConversations: true, hasPassword: false,
        avatarShape: "blob", avatarColor: "#FF6C6E", badgeLayout: "avatar", photoUrl: nil
    )
    private var profileWatchers: [UUID: AsyncThrowingStream<UserProfile?, Error>.Continuation] = [:]

    /// True: signing in makes a fresh account (the name typed, no avatar yet),
    /// so the whole sign up flow can be walked on the mock.
    private let newAccount: Bool

    init(newAccount: Bool = false) {
        self.newAccount = newAccount
    }

    func signIn(phone: String, name: String?, password: String?) async throws -> String {
        if newAccount {
            profile.phone = phone
            profile.name = name
            profile.avatarShape = nil
            profile.avatarColor = nil
        }
        return Self.demoUserId
    }
    func heartbeat(userId: String) async throws {}

    func me(userId: String) -> AsyncThrowingStream<UserProfile?, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            profileWatchers[id] = continuation
            continuation.yield(profile)
            continuation.onTermination = { [weak self] _ in self?.profileWatchers[id] = nil }
        }
    }

    func updateProfile(userId: String, patch: ProfilePatch) async throws {
        if let v = patch.name { profile.name = v }
        if let v = patch.headline { profile.headline = v }
        if let v = patch.company { profile.company = v }
        if let v = patch.location { profile.location = v }
        if let v = patch.tags { profile.tags = v }
        if let v = patch.lookingFor { profile.lookingFor = v }
        if let v = patch.offers { profile.offers = v }
        if let v = patch.hobbies { profile.hobbies = v }
        if let v = patch.appearance { profile.appearance = v }
        if let v = patch.californiaMode { profile.californiaMode = v }
        if let v = patch.recordConversations { profile.recordConversations = v }
        if let v = patch.avatarShape { profile.avatarShape = v }
        if let v = patch.avatarColor { profile.avatarColor = v }
        if let v = patch.badgeLayout { profile.badgeLayout = v }
        profileWatchers.values.forEach { $0.yield(profile) }
    }

    func uploadImage(_ jpeg: Data) async throws -> String { "mock-storage" }
    func setPhoto(userId: String, storageId: String?) async throws {}
    func moments(userId: String) -> AsyncThrowingStream<[Moment], Error> { once([]) }
    func addMoment(userId: String, storageId: String, caption: String?) async throws {}
    func removeMoment(userId: String, momentId: String) async throws {}

    /// Cycles idle -> match (approaching) -> talking -> connected so every
    /// badge state can be seen without a second phone.
    func badgeState(userId: String) -> AsyncThrowingStream<BadgeState, Error> {
        if DemoReel.isOn { return demoBadgeState() }
        return AsyncThrowingStream { continuation in
            let task = Task {
                let steps: [(BadgeMode, Double)] = [(.idle, 0), (.match, 0.2), (.match, 0.5), (.match, 0.85), (.talking, 1), (.connected, 1)]
                while !Task.isCancelled {
                    for (mode, closeness) in steps {
                        continuation.yield(BadgeState(
                            mode: mode, glow: closeness, color: mode == .idle ? nil : "#87D9FB",
                            frontTag: mode == .idle ? nil : "Product designer",
                            peerId: mode == .idle ? nil : "p1", peerName: mode == .idle ? nil : "Maya",
                            peerAvatarShape: "blob", peerAvatarColor: "#3BB52D", closeness: closeness,
                            conversationId: nil, recordConversations: true, californiaMode: false,
                            keywords: mode == .idle ? nil : ["Agent design", "iOS engineers", "Film photos"]
                        ))
                        try? await Task.sleep(for: .seconds(4))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Demo reel: idle, then Maya approaching (closeness rising in small steps
    /// so the tint grows smoothly), then talking in a conversation (the meet
    /// moment and the recording pill), then saved, once.
    private func demoBadgeState() -> AsyncThrowingStream<BadgeState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                func state(_ mode: BadgeMode, _ closeness: Double) -> BadgeState {
                    BadgeState(
                        mode: mode, glow: closeness, color: mode == .idle ? nil : "#87D9FB",
                        frontTag: mode == .idle ? nil : "Product designer",
                        peerId: mode == .idle ? nil : "p1", peerName: mode == .idle ? nil : "Maya",
                        peerAvatarShape: "blob", peerAvatarColor: "#3BB52D", closeness: closeness,
                        conversationId: mode == .talking ? "demo-conversation" : nil,
                        recordConversations: true, californiaMode: false,
                        keywords: mode == .idle ? nil : ["Agent design", "iOS engineers", "Film photos"]
                    )
                }
                continuation.yield(state(.idle, 0))
                try? await Task.sleep(for: .seconds(DemoReel.approachDelay))
                for i in 1...18 where !Task.isCancelled {
                    continuation.yield(state(.match, 0.05 * Double(i)))
                    try? await Task.sleep(for: .milliseconds(600))
                }
                guard !Task.isCancelled else { return }
                continuation.yield(state(.talking, 1))
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                continuation.yield(state(.connected, 1))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func peers(userId: String) -> AsyncThrowingStream<[Peer], Error> { once([]) }
    func uploadToken(userId: String, peerId: String, token: String) async throws {}
    func reportDistance(userId: String, peerId: String, meters: Double) async throws {}
    func setRanging(userId: String, on: Bool) async throws {}
    func finishConversation(id: String, transcript: String?) async throws {}

    func people(userId: String) -> AsyncThrowingStream<[PersonSummary], Error> { once(Self.allPeople) }

    func personDetail(userId: String, otherId: String) -> AsyncThrowingStream<PersonDetail?, Error> {
        guard let p = Self.allPeople.first(where: { $0.id == otherId }) else { return once(nil) }
        let met = p.connectedAt
        let detail = PersonDetail(
            person: PersonProfile(
                id: p.id, name: p.name, headline: p.headline, company: p.company, location: p.location,
                tags: p.tags, hobbies: ["Bouldering", "Film photos"], avatarShape: p.avatarShape,
                avatarColor: p.avatarColor, photoUrl: nil
            ),
            connectedAt: met,
            conversation: ConversationInfo(
                startedAt: met - 6 * 60_000, endedAt: met, summary: p.lastSummary,
                topics: ["Design systems", "Hiring", "Hackathons"],
                followUp: "Hey \(p.name ?? "there"), great talking at Cal Hacks! Want to grab coffee next week?"
            ),
            timeline: [
                TimelineItem(kind: "met", text: "Met at Cal Hacks", at: met - 6 * 60_000),
                TimelineItem(kind: "saved", text: "Saved to People", at: met),
            ]
        )
        return once(detail)
    }
    func currentPerson(userId: String) -> AsyncThrowingStream<String?, Error> { once(nil) }
    func markMet(userId: String, otherId: String) async throws {}

    /// Sample people so the People tab has something to show.
    private static let people: [PersonSummary] = {
        let now = Date().timeIntervalSince1970 * 1000
        return [
            PersonSummary(id: "p1", name: "Maya", headline: "Product designer", company: "Figma",
                          location: "San Francisco, CA", tags: ["Product designer", "Climbing"],
                          avatarShape: "blob", avatarColor: "#3BB52D", photoUrl: nil, connectedAt: now - 20 * 60_000,
                          lastSummary: "Maya leads design systems at Figma and is looking for iOS engineers for a side project."),
            PersonSummary(id: "p2", name: "Daniel Okafor", headline: "ML engineer", company: "Anthropic",
                          location: "Berkeley, CA", tags: ["Startup founder"],
                          avatarShape: "flower", avatarColor: "#EB8FFF", photoUrl: nil, connectedAt: now - 95 * 60_000,
                          lastSummary: "Daniel works on evals and wants to try the badge at his next meetup."),
        ]
    }()

    private static var allPeople: [PersonSummary] { DemoReel.isOn ? people + demoPeople : people }

    /// Extra people for the demo reel, so the People list scrolls.
    private static let demoPeople: [PersonSummary] = {
        let now = Date().timeIntervalSince1970 * 1000
        let rows: [(String, String, String, String, String, String, String, Double)] = [
            ("p3", "Priya Raman", "Robotics researcher", "Berkeley AI Research", "Berkeley, CA", "puzzle", "#FFC83D", 140),
            ("p4", "Leo Martins", "Founding engineer", "Stealth startup", "San Francisco, CA", "blob", "#87D9FB", 190),
            ("p5", "Hana Kim", "Hardware designer", "Cal Hacks", "Oakland, CA", "flower", "#FF6C6E", 240),
            ("p6", "Sam Whitaker", "Product manager", "Notion", "San Francisco, CA", "blob", "#EB8FFF", 300),
            ("p7", "Ana Lucia Torres", "Data scientist", "UC Berkeley", "Berkeley, CA", "pill", "#3BB52D", 380),
            ("p8", "Jordan Lee", "iOS engineer", "Airbnb", "San Francisco, CA", "flower", "#87D9FB", 460),
            ("p9", "Mei Chen", "Startup founder", "Y Combinator", "Palo Alto, CA", "blob", "#FFC83D", 540),
        ]
        return rows.map { r in
            PersonSummary(id: r.0, name: r.1, headline: r.2, company: r.3, location: r.4, tags: [r.2],
                          avatarShape: r.5, avatarColor: r.6, photoUrl: nil, connectedAt: now - r.7 * 60_000,
                          lastSummary: "\(r.1.split(separator: " ").first ?? "") talked about \(r.2.lowercased()) work and swapped ideas for a weekend project.")
        }
    }()

    private func once<T>(_ value: T) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in continuation.yield(value) }
    }
}
