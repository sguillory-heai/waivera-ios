import Foundation

/// Where the Firebase session is persisted. Keychain on Apple platforms; tests and Linux
/// use `InMemoryTokenStore`. Tokens never go to `UserDefaults` or logs.
public protocol TokenStore: Sendable {
    /// `nil` when no session is stored. Throws `TokenStoreError.locked` when a session may exist
    /// but cannot be read yet (the device has not been unlocked since it restarted): that is
    /// not "signed out", and callers must not clean up as if it were (IS-03).
    func load() throws -> FirebaseSession?
    func save(_ session: FirebaseSession) throws
    func clear() throws
}

public enum TokenStoreError: Error, Equatable, Sendable {
    /// The store is protected until the user unlocks the device; try again later.
    case locked
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let value: LockedValue<FirebaseSession?>

    private let lockedCell = LockedValue(false)

    public init(_ session: FirebaseSession? = nil) {
        value = LockedValue(session)
    }

    /// Tests: makes `load()` behave like a Keychain read before the first unlock.
    public func setLocked(_ locked: Bool) { lockedCell.update { $0 = locked } }

    public func load() throws -> FirebaseSession? {
        if lockedCell.get() { throw TokenStoreError.locked }
        return value.get()
    }
    public func save(_ session: FirebaseSession) throws { value.update { $0 = session } }
    public func clear() throws { value.update { $0 = nil } }
}

#if canImport(Security)
    import Security

    /// Stores the session as one generic-password item that is never synced or migrated to
    /// another device. Readable after the first unlock since boot, so a push that wakes the app
    /// while the phone is locked still finds the session; before that first unlock a read
    /// reports `TokenStoreError.locked` instead of "no session" (IS-03).
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
            if status == errSecInteractionNotAllowed { throw TokenStoreError.locked }
            guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
            return try JSONDecoder().decode(FirebaseSession.self, from: data)
        }

        public func save(_ session: FirebaseSession) throws {
            let data = try JSONEncoder().encode(session)
            let update: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
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
