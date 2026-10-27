import Foundation

/// Supplies the signed-in user's Firebase ID token.
public protocol AuthTokenProvider: Sendable {
    /// The current token, or a refreshed one when `forceRefresh` is true; `nil` when signed out.
    func idToken(forceRefresh: Bool) async throws -> String?
}

/// Who is signed in to Firebase. Changes only on sign-in, sign-out or a different user:
/// a token refresh is not an identity change (fixes the Expo re-bootstrap bug, 01 §2).
public struct FirebaseIdentity: Equatable, Sendable {
    public var uid: String
    public var email: String?
    public var displayName: String?

    public init(uid: String, email: String?, displayName: String?) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
    }
}

/// Owns the Firebase session: persistence, proactive refresh, one shared refresh at a time,
/// and the identity stream. Every thrown error is a `WaiveraError`.
public actor FirebaseTokenProvider: AuthTokenProvider {
    /// Refresh this long before expiry so a request never carries an about-to-expire token.
    public static let refreshMargin: TimeInterval = 300

    private let auth: any FirebaseAuthenticating
    private let store: any TokenStore
    private let clock: any WaiveraClock
    private var session: FirebaseSession?
    private var refreshTask: Task<FirebaseSession, any Error>?
    private let identityBroadcaster: AsyncBroadcaster<FirebaseIdentity?>
    /// The stored session could not be read because the device is still locked. Until it can,
    /// the identity stream emits nothing, so the session stays loading and no sign-out cleanup
    /// runs (IS-03).
    private var isWaitingForUnlock: Bool

    public init(auth: any FirebaseAuthenticating, store: any TokenStore, clock: any WaiveraClock = SystemClock()) {
        self.auth = auth
        self.store = store
        self.clock = clock
        switch Self.read(store) {
        case .locked:
            session = nil
            isWaitingForUnlock = true
            identityBroadcaster = AsyncBroadcaster(replays: true)
        case .stored(let stored):
            session = stored
            isWaitingForUnlock = false
            identityBroadcaster = AsyncBroadcaster(initial: stored.map(Self.identity))
        }
    }

    private enum StoredRead {
        case stored(FirebaseSession?)
        case locked
    }

    private static func read(_ store: any TokenStore) -> StoredRead {
        do {
            return .stored(try store.load())
        } catch TokenStoreError.locked {
            return .locked
        } catch {
            // An unreadable item (corrupt data) is no session.
            return .stored(nil)
        }
    }

    /// Reads the stored session again if it was locked at launch. Call when protected data
    /// becomes available and when the app comes to the foreground.
    public func reloadStoredSession() {
        guard isWaitingForUnlock, case .stored(let stored) = Self.read(store) else { return }
        isWaitingForUnlock = false
        session = stored
        identityBroadcaster.send(stored.map(Self.identity))
    }

    /// Emits the current identity, then every identity change.
    public nonisolated func identities() -> AsyncStream<FirebaseIdentity?> {
        identityBroadcaster.stream()
    }

    public var currentIdentity: FirebaseIdentity? { session.map(Self.identity) }

    public func idToken(forceRefresh: Bool) async throws -> String? {
        reloadStoredSession()
        // Locked: the session exists but is unreadable for now, which is retryable, not signed out.
        if isWaitingForUnlock { throw WaiveraError.offline }
        guard let current = session else { return nil }
        if !forceRefresh, current.expiresAt.timeIntervalSince(clock.now) > Self.refreshMargin {
            return current.idToken
        }
        return try await refreshed(from: current).idToken
    }

    public func signIn(email: String, password: String) async throws -> FirebaseIdentity {
        let newSession: FirebaseSession
        do {
            newSession = try await auth.signIn(email: email, password: password)
        } catch {
            throw WaiveraError.from(error)
        }
        install(newSession)
        return Self.identity(newSession)
    }

    /// Re-authenticates with the current password, then sets the new one (Firebase rejects a
    /// password change on a stale login).
    public func changePassword(current: String, new newPassword: String) async throws {
        guard let email = session?.email else { throw WaiveraError.signedOut }
        do {
            let fresh = try await auth.signIn(email: email, password: current)
            install(try await auth.updatePassword(newPassword, session: fresh))
        } catch {
            throw WaiveraError.from(error)
        }
    }

    /// Firebase's reset email; works signed out (01 §3, "Forgot password?").
    public func sendPasswordReset(email: String) async throws {
        do {
            try await auth.sendPasswordReset(email: email)
        } catch {
            throw WaiveraError.from(error)
        }
    }

    public func signOut() {
        isWaitingForUnlock = false
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        try? store.clear()
        identityBroadcaster.send(nil)
    }

    private func refreshed(from current: FirebaseSession) async throws -> FirebaseSession {
        if let refreshTask { return try await refreshTask.value }
        let auth = auth
        let task = Task { try await auth.refresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let next = try await task.value
            guard session?.uid == current.uid else { throw WaiveraError.signedOut }
            session = next
            try? store.save(next)
            return next
        } catch {
            throw Self.refreshFailure(WaiveraError.from(error), endSession: signOut)
        }
    }

    /// Only a definitive answer ends the session: the refresh token was revoked or is invalid,
    /// or the user was disabled or deleted. Rate limiting, an unknown code or an undecodable
    /// body (a captive portal page) keeps the session and comes back as a transient server
    /// error, so callers back off and try again (IS-02).
    private static func refreshFailure(_ error: WaiveraError, endSession: () -> Void) -> WaiveraError {
        guard case .auth(let failure) = error else { return error }
        if failure.endsSession {
            endSession()
            return .unauthorized
        }
        return .server(statusCode: failure == .tooManyAttempts ? 429 : 503)
    }

    private func install(_ newSession: FirebaseSession) {
        let changed = session?.uid != newSession.uid || isWaitingForUnlock
        isWaitingForUnlock = false
        session = newSession
        try? store.save(newSession)
        if changed { identityBroadcaster.send(Self.identity(newSession)) }
    }

    private static func identity(_ session: FirebaseSession) -> FirebaseIdentity {
        FirebaseIdentity(uid: session.uid, email: session.email, displayName: session.displayName)
    }
}
