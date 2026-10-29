import Foundation

// What the phone and the Apple Watch say to each other over WatchConnectivity.
// Compiled into the iOS app, the watch app and the watch widgets, so all three
// agree on one format. The phone owns every piece of state (BadgeStore,
// SharingStore, consent); the watch shows it and sends actions back.
//
// Transport: JSON in a one key dictionary. The latest state goes out as the
// application context (delivered even when the watch app opens later) and,
// while the watch app is reachable, as live messages a few times a second.

enum WatchLink {
    /// Dictionary keys for WatchConnectivity payloads.
    static let stateKey = "state"
    static let actionKey = "action"
    /// Bumped when the format changes in a way an older watch app can't read.
    static let version = 1
    /// Shared by the watch app and its widgets (Smart Stack and complications).
    static let appGroup = "group.com.ethanpany.hhil.watch"
    static let snapshotKey = "watchSnapshot"
}

/// Everything the watch shows, sent whole each time (small: a few hundred bytes).
struct WatchState: Codable, Equatable {
    var version = WatchLink.version
    var sentAt = Date()
    var signedIn = false
    var me: WatchAvatar?
    /// The badge is worn full screen on the lanyard (UWB on).
    var worn = false
    /// The demo (Settings > Demo) is driving the badge.
    var demo = false
    /// The match or person the badge shows right now.
    var nearest: WatchPeer?
    /// Everyone around with a distance, closest first, up to four.
    var nearby: [WatchPeer] = []
    /// When the current recording started (nil: not recording).
    var recordingStartedAt: Date?
    /// Others with me in the current encounter (2 or more: a group).
    var groupCount = 0
    /// Goes up at each "we finally met" moment (the watch taps once per step).
    var meetCount = 0
    /// California mode is asking me about recording.
    var consent: WatchConsent?
    /// Share requests waiting for me, newest first.
    var requests: [WatchShareRequest] = []
    /// Settings > Apple Watch > Handshake to share.
    var handshakeEnabled = true
    /// Someone within 1 m right now: a handshake would share with them.
    var handshakePeer: WatchPeer?
    /// The handshake in progress or just finished.
    var handshake: WatchHandshake?

    /// Same content, ignoring when it was sent (so unchanged state isn't resent).
    func sameContent(as other: WatchState) -> Bool {
        var a = self, b = other
        a.sentAt = .distantPast
        b.sentAt = .distantPast
        return a == b
    }
}

struct WatchAvatar: Codable, Equatable {
    var name: String
    /// AvatarShapeKind raw value ("blob", "flower", ...).
    var shape: String
    /// "#RRGGBB"
    var color: String
}

struct WatchPeer: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var shape: String?
    /// Their avatar color, "#RRGGBB".
    var color: String?
    /// Our pair color (matches only).
    var pairColor: String?
    var isMatch: Bool
    /// Best distance in meters, nil when unknown.
    var meters: Double?
    /// Only a coarse Bluetooth estimate.
    var coarse = false
    /// 0...1 from the respond range down to talking distance.
    var closeness = 0.0
    /// We're together (within 1 m, the badge's meet rule).
    var together = false
    /// Their top topic for me (the badge's first keyword).
    var keyword: String?

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
}

struct WatchConsent: Codable, Equatable {
    var conversationId: String
    var peerName: String?
    var isGroup: Bool
}

struct WatchShareRequest: Codable, Equatable, Identifiable {
    var id: String
    var fromName: String
    var fromColor: String?
    var fromShape: String?
    /// They offer their info (true) or ask for mine (false).
    var isOffer: Bool
    /// Offers: what they would share, by name.
    var items: [String]
}

struct WatchHandshake: Codable, Equatable {
    enum Status: String, Codable {
        /// The phone is calling the server.
        case sending
        /// My half is in; waiting for the other person's watch (2 minutes).
        case waiting
        /// Both approved: cards exchanged.
        case complete
        case expired
        case failed
    }
    var peerId: String
    var peerName: String
    var status: Status
    var sharedWithMe: Int?
    var message: String?
    var updatedAt = Date()
}

/// What the watch asks the phone to do.
enum WatchAction: Codable, Equatable {
    case requestState
    case recordingConsent(conversationId: String, agree: Bool)
    case respondShare(requestId: String, approve: Bool)
    /// The wearer approved sharing with this person after a handshake (or the button).
    case handshake(peerId: String)
    case cancelHandshake
}

extension WatchState {
    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WatchState? {
        guard let s = try? JSONDecoder().decode(WatchState.self, from: data), s.version <= WatchLink.version else { return nil }
        return s
    }
}

extension WatchAction {
    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WatchAction? { try? JSONDecoder().decode(WatchAction.self, from: data) }
}

/// The small slice the widgets read from the app group (written by the watch app).
struct WatchSnapshot: Codable, Equatable {
    var peerName: String?
    var peerColor: String?
    var meters: Double?
    var together = false
    var recordingStartedAt: Date?
    var worn = false
    var updatedAt = Date()

    init(peerName: String? = nil, peerColor: String? = nil, meters: Double? = nil, together: Bool = false,
         recordingStartedAt: Date? = nil, worn: Bool = false, updatedAt: Date = Date()) {
        self.peerName = peerName
        self.peerColor = peerColor
        self.meters = meters
        self.together = together
        self.recordingStartedAt = recordingStartedAt
        self.worn = worn
        self.updatedAt = updatedAt
    }

    init(_ s: WatchState) {
        self.init(peerName: s.nearest?.firstName, peerColor: s.nearest?.color, meters: s.nearest?.meters,
                  together: s.nearest?.together ?? false, recordingStartedAt: s.recordingStartedAt, worn: s.worn,
                  updatedAt: s.sentAt)
    }

    static func load() -> WatchSnapshot? {
        guard let data = UserDefaults(suiteName: WatchLink.appGroup)?.data(forKey: WatchLink.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: WatchLink.appGroup)?.set(data, forKey: WatchLink.snapshotKey)
    }

    /// "2.4 m", "0.8 m", "12 m".
    static func distanceText(_ meters: Double?) -> String {
        guard let m = meters else { return "--" }
        return m < 10 ? String(format: "%.1f m", m) : "\(Int(m.rounded())) m"
    }
}
