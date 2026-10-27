import Foundation

/// Where the Firebase session is persisted. Keychain on Apple platforms; tests and Linux
/// use `InMemoryTokenStore`. Tokens never go to `UserDefaults` or logs.
public protocol TokenStore: Sendable {
    func load() throws -> FirebaseSession?
    func save(_ session: FirebaseSession) throws
    func clear() throws
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let value: LockedValue<FirebaseSession?>

    public init(_ session: FirebaseSession? = nil) {
        value = LockedValue(session)
    }

    public func load() throws -> FirebaseSession? { value.get() }
    public func save(_ session: FirebaseSession) throws { value.update { $0 = session } }
    public func clear() throws { value.update { $0 = nil } }
}

#if canImport(Security)
    import Security

    /// Stores the session as one generic-password item, readable only while the device is
    /// unlocked and never synced or migrated to another device.
    public struct KeychainTokenStore: TokenStore {
        private let service: String
        private let account: String

        public init(service: String = "com.waivera.waivera.auth", account: String = "firebase-session") {
            self.service = service
            self.account = account
        }

        public func load() throws -> FirebaseSession? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
            return try JSONDecoder().decode(FirebaseSession.self, from: data)
        }

        public func save(_ session: FirebaseSession) throws {
            let data = try JSONEncoder().encode(session)
            let update: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            ]
            let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            if status == errSecItemNotFound {
                var insert = baseQuery
                insert.merge(update) { _, new in new }
                let addStatus = SecItemAdd(insert as CFDictionary, nil)
                guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
            } else if status != errSecSuccess {
                throw KeychainError(status: status)
            }
        }

        public func clear() throws {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        }

        private var baseQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
        }
    }

    public struct KeychainError: Error, Equatable {
        public let status: OSStatus
    }
#endif
