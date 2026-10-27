import Foundation
import WaiveraAPI

/// Where the push `deviceId` lives. It is not a secret, but it must survive a reinstall so
/// sprout_api replaces this device's old registration instead of keeping an orphan that sends
/// to a dead FCM token (push.md §1, IF-13). The Keychain keeps it across reinstalls;
/// `UserDefaults` does not.
public protocol DeviceIdentifierStore: Sendable {
    func load() -> String?
    func save(_ identifier: String)
}

/// Tests and Linux.
public final class InMemoryDeviceIdentifierStore: DeviceIdentifierStore {
    private let value: LockedValue<String?>

    public init(_ identifier: String? = nil) {
        value = LockedValue(identifier)
    }

    public func load() -> String? { value.get() }
    public func save(_ identifier: String) { value.update { $0 = identifier } }
}

#if canImport(Security)
    import Security

    /// A generic-password item that is never synced or migrated to another device, readable
    /// after the first unlock so a background launch can still register. It is kept by the
    /// first-launch wipe, which only removes the auth session.
    public struct KeychainDeviceIdentifierStore: DeviceIdentifierStore {
        private let service: String
        private let account: String

        public init(service: String = "com.waivera.waivera.device", account: String = "push-device-id") {
            self.service = service
            self.account = account
        }

        public func load() -> String? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data
            else { return nil }
            return String(data: data, encoding: .utf8)
        }

        public func save(_ identifier: String) {
            let update: [String: Any] = [
                kSecValueData as String: Data(identifier.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            if SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary) == errSecItemNotFound {
                var insert = baseQuery
                insert.merge(update) { _, new in new }
                SecItemAdd(insert as CFDictionary, nil)
            }
        }

        private var baseQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
        }
    }
#endif
