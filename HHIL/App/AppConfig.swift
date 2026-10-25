import Foundation

/// Which server the app talks to. Both implement the same `Backend` API.
enum BackendProvider: String, CaseIterable, Identifiable {
    case convex
    case spacetime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .convex: return "Convex"
        case .spacetime: return "SpacetimeDB"
        }
    }
}

/// Build time configuration from Config/Secrets.xcconfig (via Info.plist),
/// with an in app override for switching backends during testing.
enum AppConfig {
    private static let overrideKey = "convexURLOverride"

    /// Convex deployment URL. Settings can override it (for example a local network URL).
    static var convexURL: String? {
        if let override = UserDefaults.standard.string(forKey: overrideKey), !override.isEmpty {
            return override
        }
        return plistValue("ConvexURL")
    }

    static func setConvexURLOverride(_ url: String?) {
        UserDefaults.standard.set(url, forKey: overrideKey)
    }

    static var convexURLOverride: String? {
        UserDefaults.standard.string(forKey: overrideKey)
    }

    // MARK: Provider

    private static let providerKey = "backendProvider"

    /// The chosen provider: Settings override, else BACKEND_PROVIDER from the build, else Convex.
    static var backendProvider: BackendProvider {
        if let saved = UserDefaults.standard.string(forKey: providerKey), let p = BackendProvider(rawValue: saved) {
            return p
        }
        return plistValue("BackendProvider").flatMap(BackendProvider.init(rawValue:)) ?? .convex
    }

    static func setBackendProvider(_ provider: BackendProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
    }

    // MARK: SpacetimeDB

    private static let spacetimeHostKey = "spacetimeHostOverride"
    private static let spacetimeDatabaseKey = "spacetimeDatabaseOverride"
    static let defaultSpacetimeHost = "https://maincloud.spacetimedb.com"

    /// SpacetimeDB host, e.g. https://maincloud.spacetimedb.com or http://192.168.1.20:3000.
    static var spacetimeHost: String {
        spacetimeHostOverride ?? plistValue("SpacetimeHost") ?? defaultSpacetimeHost
    }

    /// The published database name (`spacetime publish <name>`).
    static var spacetimeDatabase: String? {
        spacetimeDatabaseOverride ?? plistValue("SpacetimeDatabase")
    }

    static var spacetimeHostOverride: String? {
        UserDefaults.standard.string(forKey: spacetimeHostKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var spacetimeDatabaseOverride: String? {
        UserDefaults.standard.string(forKey: spacetimeDatabaseKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func setSpacetimeOverride(host: String?, database: String?) {
        UserDefaults.standard.set(host, forKey: spacetimeHostKey)
        UserDefaults.standard.set(database, forKey: spacetimeDatabaseKey)
    }

    /// The agent's iMessage number, used by "Text your agent".
    static var agentPhone: String? { plistValue("AgentPhone") }

    /// Opens Messages with the agent, optionally with a first message.
    static func agentSMSURL(body: String? = nil) -> URL? {
        guard let phone = agentPhone else { return nil }
        var components = URLComponents()
        components.scheme = "sms"
        components.path = phone
        if let body { components.queryItems = [URLQueryItem(name: "body", value: body)] }
        return components.url
    }

    private static func plistValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("your-deployment"), !value.contains("your-database"), !value.hasPrefix("$(")
        else { return nil }
        return value
    }
}
