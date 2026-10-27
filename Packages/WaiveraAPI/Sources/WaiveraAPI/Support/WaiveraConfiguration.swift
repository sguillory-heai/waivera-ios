import Foundation

/// Build-time configuration. Values come from the app's `.xcconfig` files through
/// Info.plist keys; nothing is hard-coded and secrets never live in git.
public struct WaiveraConfiguration: Sendable, Equatable {
    /// Info.plist keys the app target must define (empty values count as missing).
    public enum Key: String, CaseIterable, Sendable {
        case apiBaseURL = "WaiveraAPIBaseURL"
        case firebaseAPIKey = "WaiveraFirebaseAPIKey"
        case webBaseURL = "WaiveraWebBaseURL"
    }

    public var apiBaseURL: URL
    public var firebaseAPIKey: String
    /// Web app root for the video-call and meeting handoff (03 §19); optional.
    public var webBaseURL: URL?

    public init(apiBaseURL: URL, firebaseAPIKey: String, webBaseURL: URL? = nil) {
        self.apiBaseURL = apiBaseURL
        self.firebaseAPIKey = firebaseAPIKey
        self.webBaseURL = webBaseURL
    }

    /// Reads the configuration from an Info.plist dictionary, or reports the missing keys.
    public static func load(from info: [String: Any]) -> Result<WaiveraConfiguration, MissingConfiguration> {
        func value(_ key: Key) -> String? {
            guard let raw = info[key.rawValue] as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // An unexpanded `$(VAR)` means the xcconfig did not define it.
            return trimmed.isEmpty || trimmed.hasPrefix("$(") ? nil : trimmed
        }
        // HTTPS only: ATS would refuse cleartext anyway, and tokens must never travel in clear
        // (AS-05). An `http://` value is treated as missing, so the app shows its gate.
        func secureURL(_ key: Key) -> URL? {
            guard let url = value(key).flatMap(URL.init(string:)), url.scheme?.lowercased() == "https",
                url.host?.isEmpty == false
            else { return nil }
            return url
        }
        var missing: [Key] = []
        let base = secureURL(.apiBaseURL)
        if base == nil { missing.append(.apiBaseURL) }
        let apiKey = value(.firebaseAPIKey)
        if apiKey == nil { missing.append(.firebaseAPIKey) }
        guard let base, let apiKey, missing.isEmpty else {
            return .failure(MissingConfiguration(keys: missing))
        }
        let web = secureURL(.webBaseURL)
        return .success(WaiveraConfiguration(apiBaseURL: base, firebaseAPIKey: apiKey, webBaseURL: web))
    }

    /// `{apiBase}/api/chatHub`; the `api/` segment is mandatory (hub.md §1).
    public var chatHubURL: URL { APIClient.join(apiBaseURL, "api/chatHub") }
    public var videoHubURL: URL { APIClient.join(apiBaseURL, "api/videoHub") }
}

public struct MissingConfiguration: Error, Equatable, Sendable {
    public var keys: [WaiveraConfiguration.Key]
}

extension APIClient {
    static func join(_ base: URL, _ path: String) -> URL {
        let root = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        return URL(string: root + path.drop { $0 == "/" }) ?? base
    }
}
