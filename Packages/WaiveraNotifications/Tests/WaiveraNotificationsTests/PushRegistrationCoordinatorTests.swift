import Testing

@testable import WaiveraNotifications

/// Records calls in order; can be told to fail the next registrations.
actor FakePushServer {
    enum Call: Equatable {
        case register(String)
    }

    private(set) var calls: [Call] = []
    private var failuresRemaining = 0

    struct Offline: Error {}

    func failNext(_ count: Int) { failuresRemaining = count }

    func register(_ token: String) throws {
        calls.append(.register(token))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Offline()
        }
    }
}

struct PushRegistrationCoordinatorTests {
    let server = FakePushServer()

    private func makeCoordinator() -> PushRegistrationCoordinator {
        let server = server
        return PushRegistrationCoordinator(register: { try await server.register($0) })
    }

    private func signedInCoordinator(token: String = "t1") async -> PushRegistrationCoordinator {
        let coordinator = makeCoordinator()
        await coordinator.authorizationChanged(.authorized)
        await coordinator.tokenChanged(token)
        await coordinator.didSignIn()
        return coordinator
    }

    @Test func registersExactlyOnceAfterSignIn() async {
        let coordinator = await signedInCoordinator()
        await coordinator.tokenChanged("t1")
        #expect(await server.calls == [.register("t1")])
        #expect(await coordinator.state == .registered(token: "t1"))
    }

    @Test func nothingIsSentBeforeSignInOrWithoutAToken() async {
        let coordinator = makeCoordinator()
        await coordinator.authorizationChanged(.authorized)
        await coordinator.tokenChanged("t1")
        #expect(await server.calls.isEmpty)
        let noToken = makeCoordinator()
        await noToken.authorizationChanged(.authorized)
        await noToken.didSignIn()
        #expect(await server.calls.isEmpty)
    }

    @Test func deniedPermissionNeverRegisters() async {
        let coordinator = makeCoordinator()
        await coordinator.authorizationChanged(.denied)
        await coordinator.tokenChanged("t1")
        await coordinator.didSignIn()
        #expect(await server.calls.isEmpty)
        await coordinator.authorizationChanged(.authorized)
        #expect(await server.calls == [.register("t1")])
    }

    @Test func rotatedTokenReRegisters() async {
        let coordinator = await signedInCoordinator()
        await coordinator.tokenChanged("t2")
        #expect(await server.calls == [.register("t1"), .register("t2")])
    }

    @Test func blankTokenIsIgnored() async {
        let coordinator = await signedInCoordinator()
        await coordinator.tokenChanged("   ")
        #expect(await server.calls == [.register("t1")])
    }

    @Test func signOutSendsNothingAndStopsRegistering() async {
        let coordinator = await signedInCoordinator()
        await coordinator.didSignOut()
        #expect(await coordinator.state == .idle)
        // The session's sign-out unregisters; a token refresh while signed out sends nothing.
        await coordinator.tokenChanged("t2")
        await coordinator.authorizationChanged(.provisional)
        #expect(await server.calls == [.register("t1")])
    }

    @Test func accountSwitchRegistersUnderTheNewIdentity() async {
        let coordinator = await signedInCoordinator()
        await coordinator.didSignOut()
        await coordinator.didSignIn()
        #expect(await server.calls == [.register("t1"), .register("t1")])
    }

    @Test func failedRegistrationIsNotRetriedAfterSignOut() async {
        await server.failNext(1)
        let coordinator = await signedInCoordinator()
        await coordinator.didSignOut()
        await coordinator.appBecameActive()
        #expect(await coordinator.state == .idle)
        #expect(await server.calls == [.register("t1")])
    }

    @Test func failedRegistrationRetriesOnForeground() async {
        await server.failNext(1)
        let coordinator = await signedInCoordinator()
        #expect(await coordinator.state == .failed(token: "t1"))
        await coordinator.appBecameActive()
        #expect(await coordinator.state == .registered(token: "t1"))
        await coordinator.appBecameActive()
        #expect(await server.calls == [.register("t1"), .register("t1")])
    }
}
