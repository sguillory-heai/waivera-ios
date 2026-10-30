import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraNotifications
import WaiveraRealtime

@testable import WaiveraData

/// Session and cleanup fixes for the iOS reviews (IF-05, IF-10, IS-03, IS-06, IS-07; AF-06,
/// PS-03, PS-04).
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

        init(
            store: InMemoryLocalStore,
            keyValues: InMemoryKeyValueStore,
            transport: RoutingTransport,
            clock: TestClock
        ) {
            self.store = store
            self.keyValues = keyValues
            self.transport = transport
            self.clock = clock
            environment = DataEnvironment.assemble(
                LiveServices(
                    auth: auth,
                    api: APIClient(baseURL: testBaseURL, transport: transport, tokens: auth),
                    realtime: realtime,
                    webBaseURL: nil,
                    localStore: store,
                    keyValueStore: keyValues,
                    connectivity: ManualConnectivity(),
                    clock: clock
                )
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
        #expect(
            await eventually { await latest(relaunched.environment.conversations.conversations())?.value?.count == 3 }
        )

        await transport.setOffline(false)
        let logins = await transport.count("GET api/Authentication/login")
        for _ in 0..<5 { await clock.advance(by: 60) }
        #expect(await eventually { await transport.count("GET api/Authentication/login") > logins })
        #expect(relaunched.state.isSignedIn)
    }

    @Test("AF-06: a password change the server asked for is not skipped by a later offline launch")
    func offlineLaunchKeepsThePasswordGate() async {
        let store = InMemoryLocalStore()
        let keyValues = InMemoryKeyValueStore()
        _ = await signedInRig(store: store, keyValues: keyValues)
        #expect(await eventually { await store.data(for: .bootstrap) != nil })

        // The next launch learns a password change is required.
        let gated = RoutingTransport()
        await Self.routes(gated)
        await gated.set("GET api/Authentication/login", .fixture("rest-auth-login-requires-password-change"))
        let second = Rig(store: store, keyValues: keyValues, transport: gated, clock: TestClock())
        await second.environment.launch()
        #expect(await eventually { if case .passwordChangeRequired = second.state { true } else { false } })
        #expect(await store.data(for: .bootstrap) == nil)

        // Offline after that: the gate is not bypassed with the earlier cached bootstrap.
        let offline = RoutingTransport()
        await Self.routes(offline)
        await offline.setOffline(true)
        let third = Rig(store: store, keyValues: keyValues, transport: offline, clock: TestClock())
        await third.environment.launch()
        #expect(await eventually { third.state == .bootstrapFailed(.offline) })
    }

    @Test("IF-10: offline at a cold start with nothing cached shows the bootstrap failure")
    func offlineColdStartWithoutACache() async {
        let transport = RoutingTransport()
        await Self.routes(transport)
        await transport.setOffline(true)
        let rig = Rig(
            store: InMemoryLocalStore(),
            keyValues: InMemoryKeyValueStore(),
            transport: transport,
            clock: TestClock()
        )
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

    @Test("PS-03, PS-04: Today's handled tally and reward day go at sign-out")
    func todaysPersonalValuesAreClearedAtSignOut() async {
        let keyValues = InMemoryKeyValueStore()
        let rig = await signedInRig(keyValues: keyValues)
        keyValues.set(
            Data(#"{"userId":"usr_alex_rivera","day":"2026-10-30","handled":2,"open":["dm-7"]}"#.utf8),
            forKey: StorageKey.todayHandled
        )
        keyValues.set(Data("2026-10-30".utf8), forKey: StorageKey.todayRewardBurstDay)
        keyValues.set(Data("kept".utf8), forKey: StorageKey.pushInstallationId)
        await rig.environment.session.signOut()
        #expect(keyValues.data(forKey: StorageKey.todayHandled) == nil)
        #expect(keyValues.data(forKey: StorageKey.todayRewardBurstDay) == nil)
        #expect(keyValues.data(forKey: StorageKey.pushInstallationId) != nil, "the install id survives sign-out")
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
            LiveServices(
                auth: provider,
                api: APIClient(baseURL: testBaseURL, transport: transport, tokens: provider),
                realtime: FakeRealtime(),
                webBaseURL: nil,
                localStore: store,
                keyValueStore: InMemoryKeyValueStore(),
                connectivity: ManualConnectivity(),
                clock: clock
            )
        )
        await environment.launch()
        await settle()
        #expect(environment.session.currentState == .loading)
        #expect(await store.data(for: .conversations) != nil)
        tokens.setLocked(false)
        await environment.protectedDataDidBecomeAvailable()
        #expect(await eventually { environment.session.currentState.isSignedIn })
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
