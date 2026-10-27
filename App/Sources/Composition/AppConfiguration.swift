import Foundation

/// Values from the per-environment `.xcconfig` files, read through Info.plist keys
/// (`Config/*.xcconfig`, documented in README). Empty or unexpanded values count as absent, so a
/// fresh clone builds and runs with no secrets: the configuration-missing screen, no Firebase, no push.
struct AppConfiguration: Sendable {
    /// Info.plist key names. `WaiveraAPIBaseURL`, `WaiveraFirebaseAPIKey` and `WaiveraWebBaseURL`
    /// are read by `WaiveraConfiguration` in WaiveraAPI.
    enum Key: String, CaseIterable {
        case apiBaseURL = "WaiveraAPIBaseURL"
        case webBaseURL = "WaiveraWebBaseURL"
        case firebaseAPIKey = "WaiveraFirebaseAPIKey"
        case firebaseAppID = "WaiveraFirebaseAppID"
        case firebaseSenderID = "WaiveraFirebaseSenderID"
        case firebaseProjectID = "WaiveraFirebaseProjectID"
    }

    /// Firebase Messaging options; `nil` when any value is missing, and then Firebase is not configured.
    struct FirebaseMessaging: Sendable, Equatable {
        let apiKey: String
        let appID: String
        let senderID: String
        let projectID: String
    }

    let info: [String: String]

    static let main = AppConfiguration(bundle: .main)

    init(bundle: Bundle) {
        var values: [String: String] = [:]
        for key in Key.allCases {
            if let raw = bundle.object(forInfoDictionaryKey: key.rawValue) as? String {
                values[key.rawValue] = raw
            }
        }
        info = values
    }

    init(info: [String: String]) {
        self.info = info
    }

    func value(_ key: Key) -> String? {
        guard let raw = info[key.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return raw.isEmpty || raw.hasPrefix("$(") ? nil : raw
    }

    var firebaseMessaging: FirebaseMessaging? {
        guard let apiKey = value(.firebaseAPIKey), let appID = value(.firebaseAppID),
            let senderID = value(.firebaseSenderID), let projectID = value(.firebaseProjectID)
        else { return nil }
        return FirebaseMessaging(apiKey: apiKey, appID: appID, senderID: senderID, projectID: projectID)
    }

    /// Web app root for call and meeting links; optional.
    var webBaseURL: URL? {
        value(.webBaseURL).flatMap(URL.init(string:))
    }

    /// Raw Info.plist dictionary for `WaiveraConfiguration.load(from:)`.
    var infoDictionary: [String: Any] { info }
}
