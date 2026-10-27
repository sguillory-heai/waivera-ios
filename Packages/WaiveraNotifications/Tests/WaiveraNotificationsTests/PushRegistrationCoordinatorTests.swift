import Testing

@testable import WaiveraNotifications

/// Records calls in order; can be told to fail the next registrations.
actor FakePushServer {
    enum Call: Equatable {
        case register(String)
        case invalidate
    }

    private(set) var calls: [Call] = []
    private var failuresRemaining = 0
    private var invalidationFailures = 0

    struct Offline: Error {}

    func failNext(_ count: Int) { failuresRemaining = count }
    func failInvalidations(_ count: Int) { invalidationFailures = count }

    func invalidate() throws {
        calls.append(.invalidate)
        if invalidationFailures > 0 {
            invalidationFailures -= 1
            throw Offline()
        }
    }

    func register(_ token: String) throws {
        calls.append(.register(token))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Offline()
        }
    }
}

/// The app's UserDefaults flag, in memory.
final class MemoryPendingStore: PendingInvalidationStore, @unchecked Sendable {
    private var value: Bool
    init(_ value: Bool = false) { self.value = value }
    var isPending: Bool { value }
    func setPending(_ pending: Bool) { value = pending }
}

struct PushRegistrationCoordinatorTests {
    let server = FakePushServer()
    let pending = MemoryPendingStore()

    private func makeCoordinator() -> PushRegistrationCoordinator {
        let server = server
        return PushRegistrationCoordinator(
            register: { try await server.register($0) },
            invalidate: { try await server.invalidate() },
            pending: pending
        )
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
        #expect(await server.calls == [.register("t1"), .invalidate])
    }

    @Test func accountSwitchRegistersTheFreshTokenUnderTheNewIdentity() async {
        let coordinator = await signedInCoordinator()
        await coordinator.didSignOut()
        await coordinator.didSignIn()
        #expect(await server.calls == [.register("t1"), .invalidate], "the deleted token is never sent again")
        await coordinator.tokenChanged("t2")
        #expect(await server.calls == [.register("t1"), .invalidate, .register("t2")])
    }

    @Test func signOutDeletesTheTokenSoAKeptRegistrationGoesNowhere() async {
        let coordinator = await signedInCoordinator()
        await coordinator.didSignOut()
        #expect(await server.calls.last == .invalidate)
        #expect(!pending.isPending)
    }

    @Test func aFailedTokenDeletionIsRetriedOnActivationAndAtTheNextLaunch() async {
        let coordinator = await signedInCoordinator()
        await server.failInvalidations(2)
        await coordinator.didSignOut()
        #expect(pending.isPending)
        await coordinator.appBecameActive()
        #expect(pending.isPending)
        let nextLaunch = makeCoordinator()
        await nextLaunch.launched()
        #expect(!pending.isPending)
        #expect(await server.calls.filter { $0 == .invalidate }.count == 3)
        await nextLaunch.launched()
        #expect(await server.calls.filter { $0 == .invalidate }.count == 3, "nothing pending, nothing deleted")
    }

    @Test func signingInDropsAPendingDeletion() async {
        let coordinator = await signedInCoordinator()
        await server.failInvalidations(1)
        await coordinator.didSignOut()
        await coordinator.didSignIn()
        #expect(!pending.isPending)
        await coordinator.appBecameActive()
        #expect(await server.calls.filter { $0 == .invalidate }.count == 1)
    }

    @Test func failedRegistrationIsNotRetriedAfterSignOut() async {
        await server.failNext(1)
        let coordinator = await signedInCoordinator()
        await coordinator.didSignOut()
        await coordinator.appBecameActive()
        #expect(await coordinator.state == .idle)
        #expect(await server.calls == [.register("t1"), .invalidate])
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
