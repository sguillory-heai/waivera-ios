import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraNotifications
import WaiveraRealtime

@testable import WaiveraData

/// Session, push and cleanup fixes for the iOS reviews (IF-05, IF-06, IF-10, IF-13, IS-01,
/// IS-06, IS-07, IS-08).
@Suite("Critic fixes: session and device")
struct CriticFixSessionTests {
    private struct Rig {
        let transport: RoutingTransport
        let realtime = FakeRealtime()
        let store: InMemoryLocalStore
        let keyValues: InMemoryKeyValueStore
        let auth = FakeAuth()
        let clock: TestClock
        let environment: DataEnvironment

        init(store: InMemoryLocalStore, keyValues: InMemoryKeyValueStore, transport: RoutingTransport, clock: TestClock) {
            self.store = store
            self.keyValues = keyValues
            self.transport = transport
            self.clock = clock
            environment = DataEnvironment.assemble(
                auth: auth,
                api: APIClient(baseURL: testBaseURL, transport: transport, tokens: auth),
                realtime: realtime,
                webBaseURL: nil,
                localStore: store,
                keyValueStore: keyValues,
                connectivity: ManualConnectivity(),
                clock: clock
            )
        }

        var state: SessionState { environment.session.currentState }
    }

    private static func routes(_ transport: RoutingTransport) async {
        for (route, fixture) in [
            ("GET api/Authentication/login", "rest-auth-login"),
            ("GET api/Authentication/GetUserDetailsByUserID/usr_alex_rivera", "rest-auth-get-user-details"),
            ("GET api/users/organization", "rest-users-organization"),
            ("GET api/chat/all", "rest-chat-get-all"),
            ("GET api/chat/recent-activity", "rest-chat-recent-activity"),
            ("GET api/CalendarEvent/milestones", "rest-calendar-get-milestones"),
            ("POST api/mobile-push/unregister", "rest-mobile-push-unregister"),
        ] {
            await transport.set(route, .fixture(fixture))
        }
    }

    private func signedInRig(
        store: InMemoryLocalStore = InMemoryLocalStore(),
        keyValues: InMemoryKeyValueStore = InMemoryKeyValueStore(),
        clock: TestClock = TestClock()
    ) async -> Rig {
        let transport = RoutingTransport()
        await Self.routes(transport)
        let rig = Rig(store: store, keyValues: keyValues, transport: transport, clock: clock)
        await rig.environment.launch()
        _ = await eventually { rig.state.isSignedIn }
        return rig
    }

    // MARK: IF-05, IS-06

    @Test("IF-05: a 401 that survives the refresh ends the session and wipes the caches")
    func revokedSessionSignsOut() async {
        let rig = await signedInRig()
        #expect(rig.state.isSignedIn)
        #expect(await eventually { await rig.store.data(for: .conversations) != nil })
        await rig.transport.enqueue("GET api/chat/all", .status(401), .status(401))
        await rig.environment.conversations.refresh()
        #expect(await eventually { rig.state == .signedOut(.unauthorized) })
        #expect(rig.realtime.log.stops == 1)
        #expect(await rig.store.data(for: .conversations) == nil)
        #expect(rig.auth.calls.contains("signOut"))
    }

    @Test("IF-05: a 5xx or a 403 keeps the session")
    func serverErrorsKeepTheSession() async {
        let rig = await signedInRig()
        await rig.transport.enqueue("GET api/chat/all", .status(503), .status(403))
        await rig.environment.conversations.refresh()
        await rig.environment.conversations.refresh()
        await settle()
        #expect(rig.state.isSignedIn)
        #expect(!rig.auth.calls.contains("signOut"))
    }

    // MARK: IF-10

    @Test("IF-10: offline at a cold start, the last bootstrap opens the cached app and retries")
    func offlineColdStartUsesTheCachedBootstrap() async {
        let store = InMemoryLocalStore()
        let keyValues = InMemoryKeyValueStore()
        let first = await signedInRig(store: store, keyValues: keyValues)
        #expect(first.state.isSignedIn)
        #expect(await eventually { await store.data(for: .bootstrap) != nil })

        // Relaunch with the same caches and no network.
        let transport = RoutingTransport()
        await Self.routes(transport)
        await transport.setOffline(true)
        let clock = TestClock()
        let relaunched = Rig(store: store, keyValues: keyValues, transport: transport, clock: clock)
        await relaunched.environment.launch()
        #expect(await eventually { relaunched.state.user?.id == viewerId && relaunched.state.isSignedIn })
        #expect(await eventually { await latest(relaunched.environment.conversations.conversations())?.value?.count == 3 })

        await transport.setOffline(false)
        let logins = await transport.count("GET api/Authentication/login")
        for _ in 0..<5 { await clock.advance(by: 60) }
        #expect(await eventually { await transport.count("GET api/Authentication/login") > logins })
        #expect(relaunched.state.isSignedIn)
    }

    @Test("IF-10: offline at a cold start with nothing cached shows the bootstrap failure")
    func offlineColdStartWithoutACache() async {
        let transport = RoutingTransport()
        await Self.routes(transport)
        await transport.setOffline(true)
        let rig = Rig(store: InMemoryLocalStore(), keyValues: InMemoryKeyValueStore(), transport: transport, clock: TestClock())
        await rig.environment.launch()
        #expect(await eventually { rig.state == .bootstrapFailed(.offline) })
    }

    // MARK: IS-07

    @Test("IS-07: the account's first sign-in time is kept across launches and cleared at sign-out")
    func accountSinceIsKeptAndCleared() async {
        let keyValues = InMemoryKeyValueStore()
        let clock = TestClock()
        let first = await signedInRig(keyValues: keyValues, clock: clock)
        let since = first.environment.session.accountSince
        #expect(since == clock.now)
        await clock.advance(by: 3_600)
        let relaunched = await signedInRig(keyValues: keyValues, clock: clock)
        #expect(relaunched.environment.session.accountSince == since)
        await relaunched.environment.session.signOut()
        #expect(relaunched.environment.session.accountSince == nil)
        #expect(keyValues.data(forKey: StorageKey.accountSince) == nil)
    }

    // MARK: IS-03

    @Test("IS-03: a Keychain locked at launch never signs out, and the session loads after unlock")
    func lockedKeychainAtLaunch() async throws {
        let transport = RoutingTransport()
        await Self.routes(transport)
        let clock = TestClock()
        let stored = FirebaseSession(
            uid: "fb-alex",
            email: "alex.rivera@example.com",
            displayName: nil,
            idToken: "token",
            refreshToken: "r",
            expiresAt: clock.now.addingTimeInterval(3_600)
        )
        let tokens = InMemoryTokenStore(stored)
        tokens.setLocked(true)
        let provider = FirebaseTokenProvider(auth: StaticFirebaseAuth(), store: tokens, clock: clock)
        let store = InMemoryLocalStore()
        await store.save(["cached"], for: .conversations)
        let environment = DataEnvironment.assemble(
            auth: provider,
            api: APIClient(baseURL: testBaseURL, transport: transport, tokens: provider),
            realtime: FakeRealtime(),
            webBaseURL: nil,
            localStore: store,
            keyValueStore: InMemoryKeyValueStore(),
            connectivity: ManualConnectivity(),
            clock: clock
        )
        await environment.launch()
        await settle()
        #expect(environment.session.currentState == .loading)
        #expect(await store.data(for: .conversations) != nil)
        tokens.setLocked(false)
        await environment.protectedDataDidBecomeAvailable()
        #expect(await eventually { environment.session.currentState.isSignedIn })
    }

    // MARK: IS-01

    @Test("IS-01: the first launch after an install removes a session the Keychain kept")
    func firstLaunchWipesTheKeychainSession() throws {
        let session = FirebaseSession(
            uid: "fb-previous",
            email: nil,
            displayName: nil,
            idToken: "t",
            refreshToken: "r",
            expiresAt: .distantFuture
        )
        let tokens = InMemoryTokenStore(session)
        let devices = InMemoryDeviceIdentifierStore("waivera-1-abc")
        let defaults = InMemoryKeyValueStore()
        #expect(FirstLaunchGuard.run(defaults: defaults, tokenStore: tokens))
        #expect(try tokens.load() == nil)
        #expect(devices.load() == "waivera-1-abc")

        try tokens.save(session)
        #expect(!FirstLaunchGuard.run(defaults: defaults, tokenStore: tokens))
        #expect(try tokens.load() == session)
    }

    // MARK: IF-13

    @Test("IF-13: the device id moves from UserDefaults to the Keychain store once")
    func deviceIdMigratesToTheKeychain() async throws {
        let transport = RoutingTransport()
        await transport.set("POST api/mobile-push/register", .fixture("rest-mobile-push-register"))
        let keyValues = InMemoryKeyValueStore()
        keyValues.setValue("waivera-legacy-1", forKey: StorageKey.pushInstallationId)
        let devices = InMemoryDeviceIdentifierStore()
        let push = LivePushRegistrationRepository(
            api: makeAPI(transport),
            store: keyValues,
            clock: TestClock(),
            deviceIdentifiers: devices
        )
        #expect(await push.deviceId == "waivera-legacy-1")
        #expect(devices.load() == "waivera-legacy-1")
        #expect(keyValues.data(forKey: StorageKey.pushInstallationId) == nil)
        // A reinstall clears UserDefaults; the Keychain keeps the same id.
        let reinstalled = LivePushRegistrationRepository(
            api: makeAPI(transport),
            store: InMemoryKeyValueStore(),
            clock: TestClock(),
            deviceIdentifiers: devices
        )
        #expect(await reinstalled.deviceId == "waivera-legacy-1")
    }

    // MARK: IF-06

    private func failingPush() async -> (LivePushRegistrationRepository, RoutingTransport, TestClock, InMemoryKeyValueStore) {
        let transport = RoutingTransport()
        await transport.set("POST api/mobile-push/register", .status(503))
        let clock = TestClock()
        let keyValues = InMemoryKeyValueStore()
        return (LivePushRegistrationRepository(api: makeAPI(transport), store: keyValues, clock: clock), transport, clock, keyValues)
    }

    @Test("IF-06: registration that keeps failing throws and stores no fingerprint")
    func failedRegistrationThrows() async throws {
        let (push, transport, clock, keyValues) = await failingPush()
        let result = Task { () -> WaiveraError? in
            do {
                try await push.registerAndWait(token: "fcm-1", preferences: NotificationPreferences())
                return nil
            } catch {
                return error as? WaiveraError
            }
        }
        for _ in 0..<12 {
            await settle()
            await clock.advance(by: 61)
        }
        #expect(await result.value == .server(statusCode: 503))
        #expect(await transport.count("POST api/mobile-push/register") == LivePushRegistrationRepository.maxAttempts)
        #expect(keyValues.data(forKey: StorageKey.pushFingerprint) == nil)
    }

    @Test("IF-06: the coordinator over the live repository retries on the next activation")
    func coordinatorRetriesALiveFailure() async throws {
        let (push, transport, clock, _) = await failingPush()
        let coordinator = PushRegistrationCoordinator(register: { token in
            try await push.registerAndWait(token: token, preferences: NotificationPreferences())
        })
        let signIn = Task {
            await coordinator.authorizationChanged(.authorized)
            await coordinator.tokenChanged("fcm-1")
            await coordinator.didSignIn()
        }
        for _ in 0..<24 {
            await settle()
            await clock.advance(by: 61)
        }
        await signIn.value
        #expect(await coordinator.state == .failed(token: "fcm-1"))
        let failedCalls = await transport.count("POST api/mobile-push/register")
        await transport.set("POST api/mobile-push/register", .fixture("rest-mobile-push-register"))
        let activation = Task { await coordinator.appBecameActive() }
        for _ in 0..<4 {
            await settle()
            await clock.advance(by: 1)
        }
        await activation.value
        #expect(await transport.count("POST api/mobile-push/register") == failedCalls + 1)
        #expect(await coordinator.state == .registered(token: "fcm-1"))
    }

    // MARK: IS-08

    @Test("IS-08: a download that finishes after sign-out cleanup is not cached")
    func downloadAfterClearIsDropped() async throws {
        let transport = RoutingTransport()
        let route = "GET api/chat/message/9320/attachment"
        await transport.set(route, .json("file-bytes"))
        let gate = Gate()
        await transport.setBeforeReply { request in
            if RoutingTransport.route(of: request) == route { await gate.wait() }
        }
        let attachments = LiveAttachmentsRepository(api: makeAPI(transport))
        let download = Task { try await attachments.data(forMessageId: 9320) }
        #expect(await eventually { await transport.count(route) == 1 })
        await attachments.clear()
        await gate.open()
        await #expect(throws: WaiveraError.signedOut) { try await download.value }
        // The next request goes to the network again: nothing of the first download was kept.
        _ = try await attachments.data(forMessageId: 9320)
        #expect(await transport.count(route) == 2)
    }
}

/// Holds callers until `open()`.
actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

/// Firebase that never needs to answer: the stored session is still valid.
struct StaticFirebaseAuth: FirebaseAuthenticating {
    func signIn(email: String, password: String) async throws -> FirebaseSession { throw WaiveraError.offline }
    func refresh(_ session: FirebaseSession) async throws -> FirebaseSession { session }
    func updatePassword(_ newPassword: String, session: FirebaseSession) async throws -> FirebaseSession { session }
    func sendPasswordReset(email: String) async throws {}
}
