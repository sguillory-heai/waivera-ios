import Foundation
import WaiveraAPI

/// Small device-local values: settings, the push installation id and fingerprint. Not for
/// secrets (tokens live in the Keychain through `TokenStore`).
public protocol KeyValueStore: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

extension KeyValueStore {
    public func value<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    public func setValue<T: Encodable>(_ value: T?, forKey key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}

/// Keys, namespaced so sign-out can clear user data and keep device data.
public enum StorageKey {
    public static let settings = "waivera.settings"
    /// The push `deviceId`; survives sign-out, regenerated on reinstall (09 §3).
    public static let pushInstallationId = "waivera-push-installation-id"
    public static let pushFingerprint = "waivera.push.fingerprint"
    /// The backend id the offline cache was written for; a different person starts empty.
    public static let cacheOwner = "waivera.cache.owner"
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private let storage = LockedValue<[String: Data]>([:])

    public init(_ initial: [String: Data] = [:]) {
        storage.update { $0 = initial }
    }

    public func data(forKey key: String) -> Data? { storage.get()[key] }

    public func set(_ data: Data?, forKey key: String) {
        storage.update { $0[key] = data }
    }
}

/// `UserDefaults` in app-private storage, which a reinstall clears (09 §3).
public final class UserDefaultsKeyValueStore: KeyValueStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
