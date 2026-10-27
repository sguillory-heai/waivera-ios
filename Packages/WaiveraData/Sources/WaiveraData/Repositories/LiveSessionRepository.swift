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
    /// Firebase took a new password for this uid but the backend confirmation has not landed.
    /// In memory only, and only a per-process hash of the new password, never the password.
    private var pendingConfirmation: PendingConfirmation?

    private struct PendingConfirmation: Equatable {
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

    public nonisolated var accountSince: Date? { context.accountSince }

    public func setParticipants(_ participants: [any SessionLifecycleParticipant]) {
        self.participants = participants
    }

    public nonisolated func states() -> AsyncStream<SessionState> { cell.stream() }
    public nonisolated var currentState: SessionState { cell.current }

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
        guard identity != nil else { return }
        switch cell.current {
        case .loading, .signedOut, .configurationMissing: return
        default: await signOut(reason: .unauthorized)
        }
    }

    private func identityChanged(_ newIdentity: FirebaseIdentity?) async {
        guard newIdentity?.uid != identity?.uid || cell.current == .loading else { return }
        identity = newIdentity
        if pendingConfirmation?.uid != newIdentity?.uid { pendingConfirmation = nil }
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

    private func finishBootstrap(_ outcome: Result<(UserLoginResponseDto, CurrentUser), WaiveraError>, generation: Int)
        async
    {
        guard generation == self.generation else { return }
        switch outcome {
        case .failure(.unauthorized), .failure(.forbidden):
            // A half-authenticated app is worse than the login screen (01 §2).
            await auth.signOut()
            cell.set(.signedOut(.unauthorized))
        case .failure(.offline):
            if let cached = await cachedUser(), generation == self.generation {
                await enter(cached)
                retryWhileOffline(generation: generation)
            } else if generation == self.generation {
                cell.set(.bootstrapFailed(.offline))
            }
        case .failure(let error):
            cell.set(.bootstrapFailed(error))
        case .success(let (login, user)):
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

    /// Firebase first, then `confirm-password-change` (which stamps the change date). When
    /// Firebase took the password but the confirmation failed (offline), a retry with the same
    /// new password skips Firebase, which would now reject the old one, and only confirms.
    /// Only the forced gate re-runs the bootstrap; a voluntary change keeps `.signedIn`, so the
    /// tabs and their navigation stay where they are.
    public func changePassword(current: String, new: String) async throws {
        guard let api else { throw WaiveraError.configurationMissing }
        guard let uid = identity?.uid else { throw WaiveraError.signedOut }
        let pending = PendingConfirmation(uid: uid, passwordHash: Self.hash(new))
        do {
            if pendingConfirmation != pending {
                try await auth.changePassword(current: current, new: new)
                pendingConfirmation = pending
            }
            try await api.confirmPasswordChange()
        } catch {
            throw WaiveraError.from(error)
        }
        pendingConfirmation = nil
        guard case .passwordChangeRequired = cell.current else { return }
        generation += 1
        bootstrap()
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
