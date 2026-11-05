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
    ///
    /// With `accessGroup`, the item lives in the keychain group the app shares with its
    /// notification extension, which reads it to fetch a sender's photo (WAIV-2939). A session
    /// saved before the group existed is moved into it on the next read.
    public struct KeychainTokenStore: TokenStore {
        /// Info.plist key holding the shared keychain group (`<team ID>.com.waivera.waivera.shared`).
        public static let accessGroupKey = "WaiveraKeychainGroup"

        private let service: String
        private let account: String
        private let accessGroup: String?

        public init(
            service: String = "com.waivera.waivera.auth",
            account: String = "firebase-session",
            accessGroup: String? = nil
        ) {
            self.service = service
            self.account = account
            self.accessGroup = accessGroup
        }

        /// The shared group from an Info.plist, or `nil` when the build has no team (simulator and
        /// unsigned builds), where the group's entitlement is not granted and the item stays private.
        public static func sharedAccessGroup(info: [String: Any]?) -> String? {
            guard let value = info?[accessGroupKey] as? String else { return nil }
            let parts = value.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, parts[0].count == 10,
                parts[0].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
            else { return nil }
            return value
        }

        public func load() throws -> FirebaseSession? {
            // The shared item first: if a move into the group was cut short, both exist and the
            // shared one is the newer (every save goes there).
            // A signed build missing the group's entitlement reads the private item as before
            // instead of looking signed out.
            if accessGroup != nil, let shared = try readShared() {
                return shared
            }
            guard let session = try read(anyGroupQuery) else { return nil }
            if accessGroup != nil {
                // Best effort: if the move fails the app keeps working from the private item.
                try? moveIntoGroup(session)
            }
            return session
        }

        private func readShared() throws -> FirebaseSession? {
            do {
                return try read(groupQuery)
            } catch TokenStoreError.locked {
                throw TokenStoreError.locked
            } catch {
                return nil
            }
        }

        private func read(_ base: [String: Any]) throws -> FirebaseSession? {
            var query = base
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
            do {
                try save(session, to: groupQuery)
            } catch let error as KeychainError where accessGroup != nil && error.status == errSecMissingEntitlement {
                // Without the group's entitlement the session still persists, privately.
                try save(session, to: anyGroupQuery)
            }
        }

        private func save(_ session: FirebaseSession, to query: [String: Any]) throws {
            let data = try JSONEncoder().encode(session)
            let update: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if status == errSecItemNotFound {
                var insert = query
                insert.merge(update) { _, new in new }
                let addStatus = SecItemAdd(insert as CFDictionary, nil)
                guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
            } else if status != errSecSuccess {
                throw KeychainError(status: status)
            }
        }

        /// Removes the session from every group this app can reach, so sign-out also signs the
        /// extension out.
        public func clear() throws {
            let status = SecItemDelete(anyGroupQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        }

        private func moveIntoGroup(_ session: FirebaseSession) throws {
            let stale = otherGroups()
            // Straight to the group, never the private fallback, so a failed copy deletes nothing.
            try save(session, to: groupQuery)
            for group in stale {
                var query = anyGroupQuery
                query[kSecAttrAccessGroup as String] = group
                SecItemDelete(query as CFDictionary)
            }
        }

        /// Groups other than the shared one that still hold the item.
        private func otherGroups() -> [String] {
            var query = anyGroupQuery
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitAll
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                let items = result as? [[String: Any]]
            else { return [] }
            return items.compactMap { $0[kSecAttrAccessGroup as String] as? String }.filter { $0 != accessGroup }
        }

        /// Matches the item in any group the app can read.
        private var anyGroupQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
        }

        /// The shared group when there is one; writes always go there.
        private var groupQuery: [String: Any] {
            var query = anyGroupQuery
            if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
            return query
        }
    }

    public struct KeychainError: Error, Equatable {
        public let status: OSStatus
    }
#endif
