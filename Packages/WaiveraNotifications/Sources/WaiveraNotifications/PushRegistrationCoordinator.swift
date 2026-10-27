/// Supplies the FCM registration token. The app target implements it over FirebaseMessaging;
/// tests and the fake server use a stub. Emits the current token (if any) and every refresh.
public protocol PushTokenSource: Sendable {
    func tokens() -> AsyncStream<String>
}

/// Keeps the server's push registration in step with the token, the session and the system
/// permission (09-push §5, push.md §1):
/// - registers once after sign-in (re-registering under the new identity on account switch);
/// - re-registers when FCM rotates the token, without touching the hub;
/// - unregisters before sign-out clears the session;
/// - never registers while permission is denied or not yet asked;
/// - retries a failed attempt the next time the app becomes active.
///
/// Debouncing preference bursts and persisting the last-registered fingerprint belong to the
/// `PushRegistrationRepository` behind `register` (data-layer agent).
public actor PushRegistrationCoordinator {
    public typealias Register = @Sendable (_ token: String) async throws -> Void
    public typealias Unregister = @Sendable () async throws -> Void

    public enum State: Equatable, Sendable {
        case idle
        case registered(token: String)
        case failed(token: String)
    }

    private let register: Register
    private let unregister: Unregister

    private var token: String?
    private var isSignedIn = false
    private var authorization: NotificationAuthorization = .notDetermined
    public private(set) var state: State = .idle

    public init(register: @escaping Register, unregister: @escaping Unregister) {
        self.register = register
        self.unregister = unregister
    }

    public func tokenChanged(_ newToken: String) async {
        let trimmed = newToken.trimmingWhitespace
        guard !trimmed.isEmpty, trimmed != token else { return }
        token = trimmed
        await registerIfNeeded(force: false)
    }

    public func authorizationChanged(_ newValue: NotificationAuthorization) async {
        let wasAllowed = NotificationPermissionPolicy.allowsRegistration(authorization)
        authorization = newValue
        let isAllowed = NotificationPermissionPolicy.allowsRegistration(newValue)
        if isAllowed, !wasAllowed {
            await registerIfNeeded(force: false)
        }
    }

    /// Call when the session becomes signed in (including an account switch).
    public func didSignIn() async {
        isSignedIn = true
        await registerIfNeeded(force: true)
    }

    /// Call before the session is cleared. Returns `false` when the unregister call failed; sign-out
    /// continues either way, and the server deactivates the row on the next token error.
    @discardableResult
    public func prepareForSignOut() async -> Bool {
        defer {
            isSignedIn = false
            state = .idle
        }
        guard isSignedIn else { return true }
        do {
            try await unregister()
            return true
        } catch {
            return false
        }
    }

    /// Notification preferences changed; the repository debounces and sends one registration.
    public func preferencesChanged() async {
        await registerIfNeeded(force: true)
    }

    /// The app came to the foreground: retry a registration that failed.
    public func appBecameActive() async {
        if case .failed = state {
            await registerIfNeeded(force: true)
        }
    }

    private func registerIfNeeded(force: Bool) async {
        guard isSignedIn, let sent = token, NotificationPermissionPolicy.allowsRegistration(authorization) else {
            return
        }
        if !force, state == .registered(token: sent) { return }
        let outcome: State
        do {
            try await register(sent)
            outcome = .registered(token: sent)
        } catch {
            outcome = .failed(token: sent)
        }
        // A newer token or a sign-out may have arrived while awaiting; that call owns the state.
        guard isSignedIn, token == sent else { return }
        state = outcome
    }
}

private extension String {
    var trimmingWhitespace: String {
        var scalars = Substring(self)
        while let first = scalars.first, first.isWhitespace { scalars.removeFirst() }
        while let last = scalars.last, last.isWhitespace { scalars.removeLast() }
        return String(scalars)
    }
}
