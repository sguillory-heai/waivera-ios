import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

/// Records the lifecycle calls and whether Firebase was still signed in at each one.
final class RecordingParticipant: SessionLifecycleParticipant, @unchecked Sendable {
    let auth: FakeAuth
    private let log = LockedValue<[String]>([])

    init(auth: FakeAuth) { self.auth = auth }

    var calls: [String] { log.get() }

    func sessionDidStart(_ user: CurrentUser) async { log.update { $0.append("start:\(user.id)") } }
    func sessionWillEnd() async {
        log.update { $0.append(auth.calls.contains("signOut") ? "willEnd-late" : "willEnd") }
    }
    func sessionDidEnd() async { log.update { $0.append(auth.calls.contains("signOut") ? "didEnd" : "didEnd-early") } }
}

@Suite("Session")
struct SessionTests {
    private let loginRoute = "GET api/Authentication/login"

    private struct Made {
        let session: LiveSessionRepository
        let transport: RoutingTransport
        let auth: FakeAuth
        let participant: RecordingParticipant
        let context: SessionContext
    }

    private func make(signedIn: Bool = true) async -> Made {
        let transport = RoutingTransport()
        await transport.set(loginRoute, .fixture("rest-auth-login"))
        await transport.set(
            "GET api/Authentication/GetUserDetailsByUserID/usr_alex_rivera",
            .fixture("rest-auth-get-user-details")
        )
        await transport.set("GET api/users/organization", .fixture("rest-users-organization"))
        let auth = FakeAuth(signedIn: signedIn)
        let context = SessionContext()
        let session = LiveSessionRepository(auth: auth, api: makeAPI(transport), context: context)
        let participant = RecordingParticipant(auth: auth)
        await session.setParticipants([participant])
        return Made(session: session, transport: transport, auth: auth, participant: participant, context: context)
    }

    private func signedInUser(_ state: SessionState) -> CurrentUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    @Test func bootstrapsOncePerIdentityNotPerTokenRefresh() async {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        let participant = made.participant
        let context = made.context
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        auth.emitSameIdentity()
        await settle()
        #expect(await transport.count(loginRoute) == 1)
        #expect(participant.calls == ["start:usr_alex_rivera"])
        #expect(context.currentUser?.id == viewerId)
        #expect(context.currentUser?.organization?.id == 12)
    }

    @Test func signedOutAtLaunch() async {
        let made = await make(signedIn: false)
        let session = made.session
        let transport = made.transport
        let participant = made.participant
        await session.start()
        #expect(await eventually { session.currentState == .signedOut(nil) })
        #expect(await transport.count(loginRoute) == 0)
        // Nothing started, but whatever a previous person cached is still wiped (AF-04).
        #expect(participant.calls == ["didEnd-early"])
    }

    @Test func passwordChangeGateThenConfirm() async throws {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        let participant = made.participant
        await transport.enqueue(
            loginRoute,
            .json(#"{"data":{"requiresPasswordChange":true,"userId":"usr_alex_rivera","requiresOnboarding":false}}"#)
        )
        await transport.set("POST api/Authentication/confirm-password-change", .emptyOK)
        await session.start()
        #expect(
            await eventually {
                if case .passwordChangeRequired = session.currentState { return true }
                return false
            }
        )
        #expect(participant.calls.isEmpty)
        try await session.changePassword(current: "old", new: "new-password")
        #expect(await eventually { signedInUser(session.currentState) != nil })
        #expect(auth.calls.contains("changePassword"))
        #expect(await transport.count("POST api/Authentication/confirm-password-change") == 1)
    }

    @Test func unauthorizedSignsOut() async {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        await transport.set(loginRoute, .fixture("rest-error-apiresponse-unauthorized", status: 401))
        await session.start()
        #expect(await eventually { session.currentState == .signedOut(.unauthorized) })
        #expect(auth.calls.contains("signOut"))
    }

    @Test func serverErrorKeepsFirebaseAndRetries() async {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        await transport.enqueue(loginRoute, .fixture("rest-error-controller-500", status: 500))
        await session.start()
        #expect(
            await eventually {
                if case .bootstrapFailed = session.currentState { return true }
                return false
            }
        )
        #expect(!auth.calls.contains("signOut"))
        await session.retryBootstrap()
        #expect(await eventually { signedInUser(session.currentState) != nil })
    }

    @Test func signOutRunsWillEndBeforeFirebaseAndDidEndAfter() async {
        let made = await make()
        let session = made.session
        let auth = made.auth
        let participant = made.participant
        let context = made.context
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        await session.signOut()
        #expect(participant.calls == ["start:usr_alex_rivera", "willEnd", "didEnd"])
        #expect(auth.calls.last == "signOut")
        #expect(session.currentState == .signedOut(nil))
        #expect(context.currentUser == nil)
    }

    @Test("AF-04: a rejected bootstrap wipes the caches even though the session never started")
    func rejectedBootstrapRunsTheCleanup() async {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let participant = made.participant
        await transport.set(loginRoute, .fixture("rest-error-apiresponse-unauthorized", status: 401))
        await session.start()
        #expect(await eventually { session.currentState == .signedOut(.unauthorized) })
        #expect(await eventually { participant.calls.contains("didEnd") })
        #expect(!participant.calls.contains { $0.hasPrefix("start") })
    }

    @Test("Auth request 1: the reset email goes through Firebase")
    func passwordReset() async throws {
        let made = await make(signedIn: false)
        let session = made.session
        let auth = made.auth
        try await session.sendPasswordReset(email: " alex.rivera@example.com ")
        #expect(auth.calls.contains("sendPasswordReset:alex.rivera@example.com"))
        await #expect(throws: WaiveraError.auth(.invalidCredentials)) {
            try await session.sendPasswordReset(email: "unknown@example.com")
        }
    }

    @Test("Auth request 3: a voluntary change never leaves .signedIn")
    func voluntaryChangeStaysSignedIn() async throws {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let participant = made.participant
        await transport.set("POST api/Authentication/confirm-password-change", .emptyOK)
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        let states = LockedValue<[SessionState]>([])
        let watcher = Task {
            for await state in session.states() { states.update { $0.append(state) } }
        }
        await settle()
        try await session.changePassword(current: "old", new: "new-password")
        await settle()
        watcher.cancel()
        #expect(!states.get().contains(.bootstrapping))
        #expect(signedInUser(session.currentState) != nil)
        #expect(await transport.count(loginRoute) == 1)
        #expect(await transport.count("POST api/Authentication/confirm-password-change") == 1)
        #expect(participant.calls == ["start:usr_alex_rivera"])
    }

    @Test("Auth request 3: after Firebase took the password, a retry only repeats the confirmation")
    func changeIsResumable() async throws {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        await transport.enqueue("POST api/Authentication/confirm-password-change", .status(503), .emptyOK)
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        await #expect(throws: WaiveraError.server(statusCode: 503)) {
            try await session.changePassword(current: "old", new: "new-password")
        }
        try await session.changePassword(current: "old", new: "new-password")
        #expect(auth.calls.filter { $0 == "changePassword" }.count == 1)
        #expect(await transport.count("POST api/Authentication/confirm-password-change") == 2)
    }

    @Test("A different new password after a failed confirmation goes through Firebase again")
    func differentPasswordRedoesFirebase() async throws {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        await transport.enqueue("POST api/Authentication/confirm-password-change", .status(503), .emptyOK)
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        _ = try? await session.changePassword(current: "old", new: "first-choice")
        try await session.changePassword(current: "first-choice", new: "second-choice")
        #expect(auth.calls.filter { $0 == "changePassword" }.count == 2)
    }

    @Test func missingConfiguration() async {
        let session = LiveSessionRepository(auth: FakeAuth(), api: nil, context: SessionContext())
        await session.start()
        #expect(session.currentState == .configurationMissing)
    }
}
