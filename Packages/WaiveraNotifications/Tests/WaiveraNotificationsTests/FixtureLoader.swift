import Foundation

/// Loads the shared push fixtures (copied from spec/fixtures) and reshapes them into what iOS
/// hands the app: `userInfo` = FCM `data` keys at the top level plus the APNs `aps` dictionary.
enum FixtureLoader {
    static func json(_ name: String) throws -> Any {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    static func userInfo(_ name: String) throws -> [AnyHashable: Any] {
        let root = try json(name)
        if let batch = root as? [[String: Any]], let first = batch.first {
            // Expo relay batch: data sits under each ticket.
            return (first["data"] as? [String: Any]) ?? [:]
        }
        guard let object = root as? [String: Any] else { throw FixtureError.shape(name) }
        guard let message = object["message"] as? [String: Any] else {
            // A bare FCM data map.
            return object
        }
        var userInfo: [AnyHashable: Any] = [:]
        for (key, value) in (message["data"] as? [String: Any]) ?? [:] {
            userInfo[key] = value
        }
        if let apns = message["apns"] as? [String: Any], let payload = apns["payload"] as? [String: Any] {
            for (key, value) in payload {
                userInfo[key] = value
            }
        }
        return userInfo
    }

    enum FixtureError: Error {
        case missing(String)
        case shape(String)
    }
}
