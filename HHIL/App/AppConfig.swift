import Foundation

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
              !value.isEmpty, !value.contains("your-deployment"), !value.hasPrefix("$(")
        else { return nil }
        return value
    }
}
