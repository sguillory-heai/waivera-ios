/// Supplies the FCM registration token. The app target implements it over FirebaseMessaging;
/// tests and the fake server use a stub. Emits the current token (if any) and every refresh.
public protocol PushTokenSource: Sendable {
    func tokens() -> AsyncStream<String>
}

/// Decides when the app hands its FCM token to the data layer (09-push §5, push.md §1):
/// - after sign-in (again after an account switch);
/// - when FCM rotates the token, without touching the hub;
/// - never while permission is denied or not yet asked, and never while signed out;
/// - again the next time the app becomes active when an attempt threw.
///
/// The `PushRegistrationRepository` behind `register` owns everything that talks to the server
/// about this device: the debounce, the stored fingerprint, retries, re-registering when the
/// notification switches change, and unregistering during sign-out. This type never
/// unregisters, so sign-out sends exactly one unregister call.
public actor PushRegistrationCoordinator {
    public typealias Register = @Sendable (_ token: String) async throws -> Void

    public enum State: Equatable, Sendable {
        case idle
        case registered(token: String)
        case failed(token: String)
    }

    private let register: Register

    private var token: String?
    private var isSignedIn = false
    private var authorization: NotificationAuthorization = .notDetermined
    public private(set) var state: State = .idle

    public init(register: @escaping Register) {
        self.register = register
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

    /// Call when the session leaves the signed-in state, for any reason. Nothing is sent: the
    /// session's own sign-out unregisters this device while requests can still authenticate.
    public func didSignOut() {
        isSignedIn = false
        state = .idle
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
