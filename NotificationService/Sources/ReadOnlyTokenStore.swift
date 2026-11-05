import WaiveraAPI

/// The app's stored session, read but never written: sign-in, sign-out and the keychain stay
/// the app's job, so a push that lands during sign-out can never put a session back. A token
/// refreshed here is kept in memory for the rest of the extension's process, and only while
/// the stored session is still the one it was refreshed from.
struct ReadOnlyTokenStore: TokenStore {
    private static let refreshed = LockedValue<FirebaseSession?>(nil)

    private let base: any TokenStore

    init(_ base: any TokenStore) {
        self.base = base
    }

    func load() throws -> FirebaseSession? {
        guard let stored = try base.load() else { return nil }
        if let fresh = Self.refreshed.get(), fresh.uid == stored.uid, fresh.refreshToken == stored.refreshToken,
            fresh.expiresAt > stored.expiresAt
        {
            return fresh
        }
        return stored
    }

    func save(_ session: FirebaseSession) throws {
        Self.refreshed.update { $0 = session }
    }

    func clear() throws {
        Self.refreshed.update { $0 = nil }
    }
}
