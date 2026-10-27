import Foundation
import WaiveraAPI

/// Bootstraps once per Firebase identity, never per token refresh (01 §2 fix), and runs the
/// single sign-out sequence (01 §6).
public actor LiveSessionRepository: SessionRepository {
    private let auth: any AuthSession
    private let api: APIClient?
    private let context: SessionContext
    private var participants: [any SessionLifecycleParticipant] = []
    private let cell = StateCell(SessionState.loading)
    private var identityTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var identity: FirebaseIdentity?
    private var startedUserId: String?
    private var generation = 0

    /// `api` is `nil` when the build has no configuration; the state is then
    /// `.configurationMissing` and nothing else runs.
    public init(auth: any AuthSession, api: APIClient?, context: SessionContext) {
        self.auth = auth
        self.api = api
        self.context = context
    }

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
    }

    private func identityChanged(_ newIdentity: FirebaseIdentity?) async {
        guard newIdentity?.uid != identity?.uid || cell.current == .loading else { return }
        identity = newIdentity
        bootstrapTask?.cancel()
        generation += 1
        if newIdentity == nil {
            await endParticipants()
            if case .signedOut = cell.current {} else { cell.set(.signedOut(nil)) }
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
        case .failure(let error):
            cell.set(.bootstrapFailed(error))
        case .success(let (login, user)):
            context.set(user)
            if login.requiresPasswordChange {
                cell.set(.passwordChangeRequired(user))
            } else if login.requiresOnboarding {
                cell.set(.onboardingRequired(user))
            } else {
                if startedUserId != user.id {
                    if startedUserId != nil { await endParticipants() }
                    context.set(user)
                    startedUserId = user.id
                    for participant in participants { await participant.sessionDidStart(user) }
                }
                cell.set(.signedIn(user))
            }
        }
    }

    public func signIn(email: String, password: String) async throws {
        do {
            _ = try await auth.signIn(email: email.trimmed, password: password)
        } catch {
            throw WaiveraError.from(error)
        }
    }

    public func changePassword(current: String, new: String) async throws {
        guard let api else { throw WaiveraError.configurationMissing }
        do {
            try await auth.changePassword(current: current, new: new)
            try await api.confirmPasswordChange()
        } catch {
            throw WaiveraError.from(error)
        }
        generation += 1
        bootstrap()
    }

    public func retryBootstrap() async {
        guard identity != nil else { return }
        generation += 1
        bootstrap()
    }

    public func signOut() async {
        generation += 1
        bootstrapTask?.cancel()
        if startedUserId != nil {
            for participant in participants { await participant.sessionWillEnd() }
        }
        await auth.signOut()
        identity = nil
        await endParticipants(alreadyEnding: true)
        cell.set(.signedOut(nil))
    }

    private func endParticipants(alreadyEnding: Bool = false) async {
        if startedUserId != nil {
            if !alreadyEnding {
                for participant in participants { await participant.sessionWillEnd() }
            }
            for participant in participants { await participant.sessionDidEnd() }
        }
        startedUserId = nil
        context.set(nil)
    }
}
