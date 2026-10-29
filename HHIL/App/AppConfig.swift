import Foundation

/// App configuration. The backend is SpacetimeDB (Maincloud); its address is
/// fixed here, not user editable.
enum AppConfig {
    /// SpacetimeDB Maincloud and the published module name (`spacetime publish hhil`).
    static let spacetimeHost = "https://maincloud.spacetimedb.com"
    static let spacetimeDatabase = "hhil"

    // MARK: One time migration

    /// Older builds could talk to Convex and saved the pick under this key.
    private static let legacyProviderKey = "backendProvider"
    /// Set once this phone has run a SpacetimeDB only build.
    private static let spacetimeOnlyKey = "backend.spacetimeOnly"

    /// A phone last signed in on Convex holds a Convex user id, which SpacetimeDB
    /// does not know: forget it once so the person signs in again. Phones that
    /// were already on SpacetimeDB (saved provider "spacetime") stay signed in.
    static func forgetConvexSignInOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: spacetimeOnlyKey) else { return }
        if defaults.string(forKey: legacyProviderKey) != "spacetime" {
            defaults.removeObject(forKey: "userId")
        }
        defaults.removeObject(forKey: legacyProviderKey)
        defaults.set(true, forKey: spacetimeOnlyKey)
    }

    /// The agent's iMessage line on Photon (shared pool). Testers must be added
    /// to the line in the Photon dashboard, then their texts arrive as blue
    /// bubbles. AGENT_PHONE in Secrets.xcconfig overrides it.
    static let photonLine = "+16289988199"
    /// Set from the signed in profile: the line Photon assigned to this person.
    @MainActor static var assignedAgentLine: String?

    @MainActor static var agentPhone: String? {
        if let line = assignedAgentLine, !line.isEmpty { return line }
        return plistValue("AgentPhone").flatMap { $0.contains("5555550123") ? nil : $0 } ?? photonLine
    }

    /// Opens Messages with the agent, optionally with a first message.
    @MainActor static func agentSMSURL(body: String? = nil) -> URL? {
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
