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

    private func make(signedIn: Bool = true) async -> (
        LiveSessionRepository, RoutingTransport, FakeAuth,
        RecordingParticipant, SessionContext
    ) {
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
        return (session, transport, auth, participant, context)
    }

    private func signedInUser(_ state: SessionState) -> CurrentUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    @Test func bootstrapsOncePerIdentityNotPerTokenRefresh() async {
        let (session, transport, auth, participant, context) = await make()
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
        let (session, transport, _, participant, _) = await make(signedIn: false)
        await session.start()
        #expect(await eventually { session.currentState == .signedOut(nil) })
        #expect(await transport.count(loginRoute) == 0)
        #expect(participant.calls.isEmpty)
    }

    @Test func passwordChangeGateThenConfirm() async throws {
        let (session, transport, auth, participant, _) = await make()
        await transport.enqueue(
            loginRoute,
            .json(#"{"data":{"requiresPasswordChange":true,"userId":"usr_alex_rivera","requiresOnboarding":false}}"#)
        )
        await transport.set("POST api/Authentication/confirm-password-change", .ok)
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
        let (session, transport, auth, _, _) = await make()
        await transport.set(loginRoute, .fixture("rest-error-apiresponse-unauthorized", status: 401))
        await session.start()
        #expect(await eventually { session.currentState == .signedOut(.unauthorized) })
        #expect(auth.calls.contains("signOut"))
    }

    @Test func serverErrorKeepsFirebaseAndRetries() async {
        let (session, transport, auth, _, _) = await make()
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
        let (session, _, auth, participant, context) = await make()
        await session.start()
        #expect(await eventually { signedInUser(session.currentState) != nil })
        await session.signOut()
        #expect(participant.calls == ["start:usr_alex_rivera", "willEnd", "didEnd"])
        #expect(auth.calls.last == "signOut")
        #expect(session.currentState == .signedOut(nil))
        #expect(context.currentUser == nil)
    }

    @Test func missingConfiguration() async {
        let session = LiveSessionRepository(auth: FakeAuth(), api: nil, context: SessionContext())
        await session.start()
        #expect(session.currentState == .configurationMissing)
    }
}
