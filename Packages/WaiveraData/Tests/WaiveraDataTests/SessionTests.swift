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

    /// sprout_api's `change-password`: answers `status` and, on 200, takes the new password like
    /// Firebase would.
    private func serveChangePassword(_ made: Made, status: Int = 200) async {
        let auth = made.auth
        let route = changePasswordRoute
        await made.transport.set(route, status == 200 ? .emptyOK : .status(status))
        await made.transport.setBeforeReply { request in
            guard status == 200,
                RoutingTransport.route(of: request) == route,
                let body = request.httpBody,
                let json = try? JSONSerialization.jsonObject(with: body) as? [String: String],
                let new = json["newPassword"]
            else { return }
            auth.password.update { $0 = new }
        }
    }

    private let changePasswordRoute = "POST api/Authentication/change-password"

    @Test func passwordChangeGateThenServerChange() async throws {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        let participant = made.participant
        await transport.enqueue(
            loginRoute,
            .json(#"{"data":{"requiresPasswordChange":true,"userId":"usr_alex_rivera","requiresOnboarding":false}}"#)
        )
        await serveChangePassword(made)
        await session.start()
        #expect(
            await eventually {
                if case .passwordChangeRequired = session.currentState { return true }
                return false
            }
        )
        #expect(participant.calls.isEmpty)
        try await session.changePassword(current: "correct", new: "Morning_walk42")
        #expect(await eventually { signedInUser(session.currentState) != nil })
        #expect(auth.calls.filter { ["reauthenticate", "signIn"].contains($0) } == ["reauthenticate", "signIn"])
        let sent = try #require(await transport.bodies(changePasswordRoute).first)
        let json = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: String])
        #expect(json == ["idToken": "fresh-token", "newPassword": "Morning_walk42"])
        #expect(auth.password.get() == "Morning_walk42")
        #expect(await transport.count("POST api/Authentication/confirm-password-change") == 0)
    }

    @Test("Password change: a wrong current password never reaches the server")
    func wrongCurrentPasswordStaysLocal() async throws {
        let made = await make()
        let session = made.session
        await serveChangePassword(made)
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        await #expect(throws: WaiveraError.auth(.invalidCredentials)) {
            try await session.changePassword(current: "wrong", new: "Morning_walk42")
        }
        #expect(await made.transport.count(changePasswordRoute) == 0)
    }

    @Test("Password change: a refused request and a stale sign-in get their own errors, and keep the session")
    func serverRefusalsMapToAuthFailures() async throws {
        let made = await make()
        let session = made.session
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        await serveChangePassword(made, status: 400)
        await #expect(throws: WaiveraError.invalidRequest) {
            try await session.changePassword(current: "correct", new: "Morning_walk42")
        }
        await serveChangePassword(made, status: 401)
        await #expect(throws: WaiveraError.auth(.requiresRecentLogin)) {
            try await session.changePassword(current: "correct", new: "Morning_walk42")
        }
        await settle()
        #expect(signedInUser(session.currentState) != nil, "a 401 here is not a revoked account")
        #expect(made.auth.password.get() == "correct")
    }

    @Test("Password change: signing back in failing ends the session and says why")
    func signBackInFailureSignsOut() async throws {
        let made = await make()
        let session = made.session
        await serveChangePassword(made)
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        made.auth.signInFailure.update { $0 = WaiveraError.offline }
        await #expect(throws: WaiveraError.auth(.passwordChangedSignInAgain)) {
            try await session.changePassword(current: "correct", new: "Morning_walk42")
        }
        #expect(session.currentState == .signedOut(.auth(.passwordChangedSignInAgain)))
        #expect(made.auth.password.get() == "Morning_walk42")
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
        await serveChangePassword(made)
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        let states = LockedValue<[SessionState]>([])
        let watcher = Task {
            for await state in session.states() { states.update { $0.append(state) } }
        }
        await settle()
        try await session.changePassword(current: "correct", new: "Morning_walk42")
        await settle()
        watcher.cancel()
        #expect(!states.get().contains(.bootstrapping))
        #expect(signedInUser(session.currentState) != nil)
        #expect(await transport.count(loginRoute) == 1)
        #expect(await transport.count(changePasswordRoute) == 1)
        #expect(participant.calls == ["start:usr_alex_rivera"])
    }

    @Test("Password change: a 5xx after Firebase took the password is finished in the same tap")
    func halfDoneChangeIsFinishedAtOnce() async throws {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        // The server set the Firebase password, then failed before stamping the date.
        await transport.enqueue(changePasswordRoute, .status(500), .emptyOK)
        await transport.setBeforeReply { _ in auth.password.update { $0 = "Morning_walk42" } }
        try await session.changePassword(current: "correct", new: "Morning_walk42")
        #expect(await transport.count(changePasswordRoute) == 2, "sent again to stamp the change")
        #expect(signedInUser(session.currentState) != nil)
    }

    @Test("Password change: a retry after a lost answer finishes with the new password")
    func retryAfterALostAnswer() async throws {
        let made = await make()
        let session = made.session
        let transport = made.transport
        let auth = made.auth
        await transport.set(changePasswordRoute, .emptyOK)
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        // The request reached the server, which changed the password, but no answer came back.
        await transport.setBeforeReply { _ in auth.password.update { $0 = "Morning_walk42" } }
        await transport.setOffline(true)
        await #expect(throws: WaiveraError.offline) {
            try await session.changePassword(current: "correct", new: "Morning_walk42")
        }
        await transport.setOffline(false)
        // The current password is refused now; the same new password proves the change and is sent again.
        try await session.changePassword(current: "correct", new: "Morning_walk42")
        #expect(await transport.count(changePasswordRoute) == 3)
        #expect(signedInUser(session.currentState) != nil)
        // A different new password is a new change, and the wrong current password says so.
        await #expect(throws: WaiveraError.auth(.invalidCredentials)) {
            try await session.changePassword(current: "correct", new: "Another_one99")
        }
    }

    @Test("Password change: a refused current password with an unrelated new one never tries the new one")
    func noExtraSignInWithoutAnEarlierAttempt() async throws {
        let made = await make()
        let session = made.session
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        await #expect(throws: WaiveraError.auth(.invalidCredentials)) {
            try await session.changePassword(current: "wrong", new: "Morning_walk42")
        }
        #expect(made.auth.calls.filter { $0 == "reauthenticate" }.count == 1)
    }

    @Test func missingConfiguration() async {
        let session = LiveSessionRepository(auth: FakeAuth(), api: nil, context: SessionContext())
        await session.start()
        #expect(session.currentState == .configurationMissing)
    }
}
