/// Supplies the FCM registration token. The app target implements it over FirebaseMessaging;
/// tests and the fake server use a stub. Emits the current token (if any) and every refresh.
public protocol PushTokenSource: Sendable {
    func tokens() -> AsyncStream<String>
    /// Deletes the current token so pushes sent to it stop arriving, even when the server never
    /// heard the unregister. FCM issues a new token on the next start.
    func invalidate() async throws
}

extension PushTokenSource {
    public func invalidate() async throws {}
}

/// Remembers, across launches, that a token still needs invalidating (the app backs it with
/// `UserDefaults`; it holds a flag, never the token).
public protocol PendingInvalidationStore: Sendable {
    var isPending: Bool { get }
    func setPending(_ pending: Bool)
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
    public typealias Invalidate = @Sendable () async throws -> Void

    public enum State: Equatable, Sendable {
        case idle
        case registered(token: String)
        case failed(token: String)
    }

    private let register: Register
    private let invalidate: Invalidate
    private let pending: (any PendingInvalidationStore)?

    private var token: String?
    private var isSignedIn = false
    private var authorization: NotificationAuthorization = .notDetermined
    public private(set) var state: State = .idle

    public init(
        register: @escaping Register,
        invalidate: @escaping Invalidate = {},
        pending: (any PendingInvalidationStore)? = nil
    ) {
        self.register = register
        self.invalidate = invalidate
        self.pending = pending
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

    /// Call when the session becomes signed in (including an account switch). Registering binds
    /// the current token to the new account, so a pending invalidation is dropped.
    public func didSignIn() async {
        isSignedIn = true
        pending?.setPending(false)
        await registerIfNeeded(force: true)
    }

    /// Call when the session leaves the signed-in state, for any reason. Nothing is sent to the
    /// server here (the session's own sign-out unregisters while requests still authenticate);
    /// the token itself is deleted, so a registration the server kept points at a dead token.
    /// A failed deletion is remembered and retried at launch and on activation.
    public func didSignOut() async {
        isSignedIn = false
        state = .idle
        token = nil
        pending?.setPending(true)
        await invalidateIfPending()
    }

    /// Call once at launch, before the session is known: finishes an invalidation a previous
    /// run could not.
    public func launched() async {
        await invalidateIfPending()
    }

    /// The app came to the foreground: retry a registration or an invalidation that failed.
    public func appBecameActive() async {
        if case .failed = state {
            await registerIfNeeded(force: true)
        }
        await invalidateIfPending()
    }

    private func invalidateIfPending() async {
        guard !isSignedIn, pending?.isPending ?? true else { return }
        do {
            try await invalidate()
            if !isSignedIn { pending?.setPending(false) }
        } catch {
            // Stays pending; the next launch or activation tries again.
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
