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

extension Notification.Name {
    /// Posted after the backend provider changes; the app rebuilds its environment.
    static let backendProviderChanged = Notification.Name("backendProviderChanged")
}

/// App configuration. Both backends' addresses are fixed here (not user
/// editable); Settings only switches between them.
enum AppConfig {
    /// Convex cloud deployment (team ethan-pan, project human-human-interaction-lab).
    static let convexURL = "https://small-porpoise-293.convex.cloud"
    /// SpacetimeDB Maincloud and the published module name (`spacetime publish hhil`).
    static let spacetimeHost = "https://maincloud.spacetimedb.com"
    static let spacetimeDatabase = "hhil"

    // MARK: Provider

    private static let providerKey = "backendProvider"

    /// The provider picked in Settings, Convex by default.
    static var backendProvider: BackendProvider {
        UserDefaults.standard.string(forKey: providerKey).flatMap(BackendProvider.init(rawValue:)) ?? .convex
    }

    static func setBackendProvider(_ provider: BackendProvider) {
        UserDefaults.standard.set(provider.rawValue, forKey: providerKey)
        NotificationCenter.default.post(name: .backendProviderChanged, object: nil)
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
