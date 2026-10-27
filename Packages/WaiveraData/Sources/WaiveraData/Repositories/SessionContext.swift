import Foundation
import WaiveraAPI

/// The signed-in user, readable synchronously by every repository. Set by the session
/// coordinator before any participant starts and cleared after they stop.
public final class SessionContext: Sendable {
    private let user = LockedValue<CurrentUser?>(nil)
    private let since = LockedValue<Date?>(nil)

    public init(user: CurrentUser? = nil) {
        self.user.update { $0 = user }
    }

    public var currentUser: CurrentUser? { user.get() }

    public func set(_ newUser: CurrentUser?) {
        user.update { $0 = newUser }
        if newUser == nil { since.update { $0 = nil } }
    }

    /// When this person first signed in on this device (kept across launches); see
    /// `SessionRepository.accountSince`.
    public var accountSince: Date? { since.get() }

    func setAccountSince(_ date: Date?) {
        since.update { $0 = date }
    }

    /// The backend id, or `.signedOut` for callers that need one.
    func requireUser() throws -> CurrentUser {
        guard let current = currentUser else { throw WaiveraError.signedOut }
        return current
    }
}

/// Firebase as the session sees it. `FirebaseTokenProvider` conforms; fakes implement it for
/// tests and the fake server.
public protocol AuthSession: AuthTokenProvider {
    /// Emits the current identity, then only real identity changes (never token refreshes).
    func identities() -> AsyncStream<FirebaseIdentity?>
    func signIn(email: String, password: String) async throws -> FirebaseIdentity
    func changePassword(current: String, new: String) async throws
    func sendPasswordReset(email: String) async throws
    func signOut() async
}

extension FirebaseTokenProvider: AuthSession {}

/// Something that starts with a signed-in session and must be torn down at sign-out, in the
/// order the session repository calls them.
public protocol SessionLifecycleParticipant: Sendable {
    /// The gate passed; the user is fully signed in.
    func sessionDidStart(_ user: CurrentUser) async
    /// Before Firebase is cleared, while requests can still authenticate (push unregister).
    func sessionWillEnd() async
    /// After Firebase is cleared: drop caches, the outbox and files. Runs on every transition
    /// to signed out, also when the session never fully started (a rejected bootstrap, a revoked
    /// Firebase user on a cold start), so nothing a previous person left on the device survives.
    func sessionDidEnd() async
}
