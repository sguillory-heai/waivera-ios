import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraNotifications
import WaiveraRealtime

@testable import WaiveraData

/// Device and push fixes for the iOS reviews (IF-06, IF-13, IS-01, IS-08).
@Suite("Critic fixes: device and push")
struct CriticFixDeviceTests {
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

    private func failingPush() async -> PushRig {
        let transport = RoutingTransport()
        await transport.set("POST api/mobile-push/register", .status(503))
        let clock = TestClock()
        let keyValues = InMemoryKeyValueStore()
        let push = LivePushRegistrationRepository(api: makeAPI(transport), store: keyValues, clock: clock)
        return PushRig(push: push, transport: transport, clock: clock, store: keyValues)
    }

    @Test("IF-06: registration that keeps failing throws and stores no fingerprint")
    func failedRegistrationThrows() async throws {
        let made = await failingPush()
        let push = made.push
        let transport = made.transport
        let clock = made.clock
        let keyValues = made.store
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
        let made = await failingPush()
        let push = made.push
        let transport = made.transport
        let clock = made.clock
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
