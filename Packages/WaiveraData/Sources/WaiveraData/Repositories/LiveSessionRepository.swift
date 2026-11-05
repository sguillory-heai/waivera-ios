import Foundation
import WaiveraAPI

/// Bootstraps once per Firebase identity, never per token refresh (01 §2 fix), and runs the
/// single sign-out sequence (01 §6).
///
/// - A 401 that survives a token refresh means sprout_api revoked the account: the session
///   ends with `.signedOut(.unauthorized)` and the full teardown (IF-05, IS-06).
/// - Offline at a cold start with this person's last bootstrap cached, the session starts
///   from the cache so cached chats and schedule stay reachable, and the backend login is
///   retried in the background (IF-10, spec 07).
public actor LiveSessionRepository: SessionRepository {
    /// Longest wait between background retries of an offline bootstrap.
    static let maxOfflineRetryDelay: Duration = .seconds(60)

    private let auth: any AuthSession
    private let api: APIClient?
    private let context: SessionContext
    private let localStore: (any LocalStore)?
    private let clock: any WaiveraClock
    private var rejectionTask: Task<Void, Never>?
    private var offlineRetryTask: Task<Void, Never>?
    private var participants: [any SessionLifecycleParticipant] = []
    private let cell = StateCell(SessionState.loading)
    private var identityTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var identity: FirebaseIdentity?
    private var startedUserId: String?
    private var generation = 0
    /// The last new password sent to `change-password`, for a retry after a lost answer. In
    /// memory only, and only a per-process hash of the new password, never the password.
    private var lastPasswordAttempt: PasswordAttempt?
    /// True while a password change runs. The server's change ends every Firebase session until
    /// we sign back in, so a rejected request meanwhile must not end this one.
    private var isChangingPassword = false

    private struct PasswordAttempt: Equatable {
        var uid: String
        var passwordHash: Int
    }

    /// `api` is `nil` when the build has no configuration; the state is then
    /// `.configurationMissing` and nothing else runs.
    /// `localStore` keeps the last successful bootstrap for an offline cold start; it is the
    /// user cache, wiped at sign-out.
    public init(
        auth: any AuthSession,
        api: APIClient?,
        context: SessionContext,
        localStore: (any LocalStore)? = nil,
        clock: any WaiveraClock = SystemClock()
    ) {
        self.auth = auth
        self.api = api
        self.context = context
        self.localStore = localStore
        self.clock = clock
    }

    nonisolated public var accountSince: Date? { context.accountSince }

    public func setParticipants(_ participants: [any SessionLifecycleParticipant]) {
        self.participants = participants
    }

    nonisolated public func states() -> AsyncStream<SessionState> { cell.stream() }
    nonisolated public var currentState: SessionState { cell.current }

    public func start() async {
        guard identityTask == nil else { return }
        guard api != nil else {
            cell.set(.configurationMissing)
            return
        }
        let identities = auth.identities()
        identityTask = Task {
            for await identity in identities {
                await self.identityChanged(identity)
            }
        }
        if let rejections = api?.rejections.stream() {
            rejectionTask = Task {
                for await _ in rejections { await self.sessionRejected() }
            }
        }
    }

    /// The server refused a freshly refreshed token: the account is gone or disabled.
    private func sessionRejected() async {
        guard identity != nil, !isChangingPassword else { return }
        switch cell.current {
        case .loading, .signedOut, .configurationMissing: return
        default: await signOut(reason: .unauthorized)
        }
    }

    private func identityChanged(_ newIdentity: FirebaseIdentity?) async {
        guard newIdentity?.uid != identity?.uid || cell.current == .loading else { return }
        identity = newIdentity
        if lastPasswordAttempt?.uid != newIdentity?.uid { lastPasswordAttempt = nil }
        bootstrapTask?.cancel()
        offlineRetryTask?.cancel()
        generation += 1
        if newIdentity == nil {
            let wasSignedIn = startedUserId != nil
            await endParticipants()
            // Firebase dropped a session the user did not end (a revoked refresh token): say why.
            if case .signedOut = cell.current {} else { cell.set(.signedOut(wasSignedIn ? .unauthorized : nil)) }
            return
        }
        bootstrap()
    }

    private func bootstrap() {
        guard let identity, let api else { return }
        let current = generation
        cell.set(.bootstrapping)
        bootstrapTask = Task {
            let outcome = await Self.loadUser(identity: identity, api: api)
            await self.finishBootstrap(outcome, generation: current)
        }
    }

    private static func loadUser(identity: FirebaseIdentity, api: APIClient) async -> Result<
        (UserLoginResponseDto, CurrentUser), WaiveraError
    > {
        do {
            let login = try await api.login()
            // Profile and organization failures are not fatal (01 §2).
            let details = try? await api.userDetails(userId: login.userId)
            let organization = (try? await api.currentOrganization()).map(ProfileMapper.organization)
            let user = ProfileMapper.currentUser(
                login: login,
                identity: identity,
                details: details,
                organization: organization
            )
            return .success((login, user))
        } catch {
            return .failure(WaiveraError.from(error))
        }
    }

    /// Starts the participants for `user` (once per backend id) and shows the app.
    private func enter(_ user: CurrentUser) async {
        context.set(user)
        if startedUserId != user.id {
            if startedUserId != nil { await endParticipants() }
            context.set(user)
            startedUserId = user.id
            for participant in participants { await participant.sessionDidStart(user) }
        }
        cell.set(.signedIn(user))
    }

    /// The last bootstrap, only when it belongs to the Firebase user now signed in.
    private func cachedUser() async -> CurrentUser? {
        guard let localStore, let identity, let cached = await localStore.load(CurrentUser.self, for: .bootstrap),
            cached.firebaseUid == identity.uid
        else { return nil }
        return cached
    }

    /// Re-runs the backend login with capped backoff until it answers; a rejection then signs
    /// out like a cold-start rejection would.
    private func retryWhileOffline(generation current: Int) {
        guard let identity, let api else { return }
        offlineRetryTask?.cancel()
        let clock = clock
        offlineRetryTask = Task {
            var delay: Duration = .seconds(2)
            while !Task.isCancelled {
                try? await clock.sleep(for: delay)
                guard !Task.isCancelled else { return }
                let outcome = await Self.loadUser(identity: identity, api: api)
                if case .failure(let error) = outcome, error.isTransient {
                    delay = min(delay * 2, Self.maxOfflineRetryDelay)
                    continue
                }
                await self.finishOfflineRetry(outcome, generation: current)
                return
            }
        }
    }

    private func finishOfflineRetry(
        _ outcome: Result<(UserLoginResponseDto, CurrentUser), WaiveraError>,
        generation current: Int
    ) async {
        guard current == generation else { return }
        switch outcome {
        case .success(let (login, user)) where !login.requiresPasswordChange && !login.requiresOnboarding:
            context.set(user)
            cell.set(.signedIn(user))
            if let localStore { await localStore.save(user, for: .bootstrap) }
        case .success:
            // A gate appeared since the cached login: run the normal bootstrap to show it.
            generation += 1
            bootstrap()
        case .failure(.unauthorized), .failure(.forbidden):
            await signOut(reason: .unauthorized)
        case .failure:
            break
        }
    }

    public func signIn(email: String, password: String) async throws {
        do {
            _ = try await auth.signIn(email: email.trimmed, password: password)
        } catch {
            throw WaiveraError.from(error)
        }
    }

    public func sendPasswordReset(email: String) async throws {
        guard api != nil else { throw WaiveraError.configurationMissing }
        do {
            try await auth.sendPasswordReset(email: email.trimmed)
        } catch {
            throw WaiveraError.from(error)
        }
    }

    /// The web's server-owned flow: Firebase checks the current password and hands back a fresh
    /// ID token, sprout_api's `change-password` sets the new password and stamps the change date,
    /// and we sign back in with the new password because the server's change ended every session.
    ///
    /// The server changes Firebase before it stamps the date, so an answer that never arrived
    /// (offline, a 5xx) may hide a change that half happened. Whenever the new password already
    /// signs in, the change is sent once more with that sign-in's token: the server accepts the
    /// same password again and stamps the date, so the gate can never stay stuck.
    ///
    /// Only the forced gate re-runs the bootstrap; a voluntary change keeps `.signedIn`, so the
    /// tabs and their navigation stay where they are.
    public func changePassword(current: String, new: String) async throws {
        guard let api else { throw WaiveraError.configurationMissing }
        guard let identity, let email = identity.email else { throw WaiveraError.signedOut }
        let attempt = PasswordAttempt(uid: identity.uid, passwordHash: Self.hash(new))
        isChangingPassword = true
        defer { isChangingPassword = false }
        do {
            let idToken = try await freshToken(current: current, new: new, attempt: attempt)
            lastPasswordAttempt = attempt
            try await sendChange(api: api, idToken: idToken, new: new)
            try await signBackIn(email: email, password: new)
        } catch {
            throw Self.passwordChangeFailure(WaiveraError.from(error))
        }
        lastPasswordAttempt = nil
        guard case .passwordChangeRequired = cell.current else { return }
        generation += 1
        bootstrap()
    }

    /// A token from proving the current password. On a retry of the same change whose answer was
    /// lost, the current password may already be refused while the new one signs in: that
    /// sign-in's token then carries the change instead.
    private func freshToken(current: String, new: String, attempt: PasswordAttempt) async throws -> String {
        do {
            return try await auth.reauthenticate(password: current)
        } catch WaiveraError.auth(.invalidCredentials) where lastPasswordAttempt == attempt {
            return try await reauthenticateWithNew(new, orThrow: .auth(.invalidCredentials))
        }
    }

    /// Signs in with the new password, or throws `refusal` when Firebase says it is not the
    /// password (yet). Any other failure (offline, too many attempts) is reported as itself.
    private func reauthenticateWithNew(_ new: String, orThrow refusal: WaiveraError) async throws -> String {
        do {
            return try await auth.reauthenticate(password: new)
        } catch WaiveraError.auth(.invalidCredentials) {
            throw refusal
        }
    }

    /// Sends the change. A definitive refusal (4xx) forgets the attempt. A lost or failed answer
    /// checks whether the new password already signs in, and if so sends the change once more.
    private func sendChange(api: APIClient, idToken: String, new: String) async throws {
        do {
            try await api.changePassword(ChangePasswordRequest(idToken: idToken, newPassword: new))
        } catch {
            let failure = WaiveraError.from(error)
            guard failure.isTransient || failure == .invalidResponse else {
                lastPasswordAttempt = nil
                throw failure
            }
            let retryToken = try await reauthenticateWithNew(new, orThrow: failure)
            try await api.changePassword(ChangePasswordRequest(idToken: retryToken, newPassword: new))
        }
    }

    /// The new password is saved whatever happens here. If Firebase will not take it right now
    /// (offline), the old session is already dead server-side, so end it and say why on sign-in.
    private func signBackIn(email: String, password: String) async throws {
        do {
            _ = try await auth.signIn(email: email, password: password)
        } catch {
            lastPasswordAttempt = nil
            await signOut(reason: .auth(.passwordChangedSignInAgain))
            throw WaiveraError.auth(.passwordChangedSignInAgain)
        }
    }

    /// A 401 from `change-password` survives the client's one token refresh only when the sign-in
    /// is not recent enough: ask for the current password again.
    private static func passwordChangeFailure(_ error: WaiveraError) -> WaiveraError {
        error == .unauthorized ? .auth(.requiresRecentLogin) : error
    }

    private static func hash(_ password: String) -> Int {
        var hasher = Hasher()
        hasher.combine(password)
        return hasher.finalize()
    }

    public func retryBootstrap() async {
        guard identity != nil else { return }
        generation += 1
        bootstrap()
    }

    public func signOut() async {
        await signOut(reason: nil)
    }

    private func signOut(reason: WaiveraError?) async {
        generation += 1
        bootstrapTask?.cancel()
        offlineRetryTask?.cancel()
        if startedUserId != nil {
            for participant in participants { await participant.sessionWillEnd() }
        }
        identity = nil
        await auth.signOut()
        await endParticipants(alreadyEnding: true)
        cell.set(.signedOut(reason))
    }

    /// Every way into signed out ends here (AF-04): a started session is torn down in order, and
    /// one that never started still has its caches, outbox and files wiped.
    private func endParticipants(alreadyEnding: Bool = false) async {
        if startedUserId != nil, !alreadyEnding {
            for participant in participants { await participant.sessionWillEnd() }
        }
        for participant in participants { await participant.sessionDidEnd() }
        startedUserId = nil
        context.set(nil)
    }
}

// MARK: - Bootstrap outcome

extension LiveSessionRepository {
    private func finishBootstrap(
        _ outcome: Result<(UserLoginResponseDto, CurrentUser), WaiveraError>,
        generation: Int
    ) async {
        guard generation == self.generation else { return }
        switch outcome {
        case .failure(.unauthorized), .failure(.forbidden):
            // A half-authenticated app is worse than the login screen (01 §2).
            await auth.signOut()
            cell.set(.signedOut(.unauthorized))
        case .failure(.offline):
            await finishOffline(generation: generation)
        case .failure(let error):
            cell.set(.bootstrapFailed(error))
        case .success(let (login, user)):
            await finishSignedIn(login, user: user)
        }
    }

    /// Offline with this person's last bootstrap cached: start from the cache and keep retrying.
    private func finishOffline(generation: Int) async {
        if let cached = await cachedUser(), generation == self.generation {
            await enter(cached)
            retryWhileOffline(generation: generation)
        } else if generation == self.generation {
            cell.set(.bootstrapFailed(.offline))
        }
    }

    private func finishSignedIn(_ login: UserLoginResponseDto, user: CurrentUser) async {
        context.set(user)
        if login.requiresPasswordChange || login.requiresOnboarding {
            // An offline launch must not open the app past a gate from a stale bootstrap
            // (Android AF-06).
            if let localStore { await localStore.remove(.bootstrap) }
        }
        if login.requiresPasswordChange {
            cell.set(.passwordChangeRequired(user))
        } else if login.requiresOnboarding {
            cell.set(.onboardingRequired(user))
        } else {
            await enter(user)
            if let localStore { await localStore.save(user, for: .bootstrap) }
        }
    }
}
