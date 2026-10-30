import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Push registration")
struct PushRegistrationTests {
    private let registerRoute = "POST api/mobile-push/register"
    private let unregisterRoute = "POST api/mobile-push/unregister"

    private func make() async -> PushRig {
        let transport = RoutingTransport()
        await transport.set(registerRoute, .fixture("rest-mobile-push-register"))
        await transport.set(unregisterRoute, .fixture("rest-mobile-push-unregister"))
        let clock = TestClock()
        let store = InMemoryKeyValueStore()
        let push = LivePushRegistrationRepository(api: makeAPI(transport), store: store, clock: clock)
        return PushRig(push: push, transport: transport, clock: clock, store: store)
    }

    private func body(_ transport: RoutingTransport, _ index: Int = 0) async throws -> [String: Any] {
        let bodies = await transport.bodies(registerRoute)
        return try #require(JSONSerialization.jsonObject(with: bodies[index]) as? [String: Any])
    }

    @Test func registersFCMOnceForTheSameFingerprint() async throws {
        let made = await make()
        let push = made.push
        let transport = made.transport
        let clock = made.clock
        await push.register(token: "fcm-1", preferences: NotificationPreferences())
        await settle()
        await clock.advance(by: 0.5)
        await push.settle()
        #expect(await transport.count(registerRoute) == 1)
        let json = try await body(transport)
        #expect(json["provider"] as? String == "fcm")
        #expect(json["platform"] as? String == "ios")
        #expect((json["deviceId"] as? String)?.hasPrefix("waivera-") == true)

        await push.register(token: "fcm-1", preferences: NotificationPreferences())
        await settle()
        await clock.advance(by: 0.5)
        await push.settle()
        #expect(await transport.count(registerRoute) == 1)
    }

    @Test func burstsAreDebouncedAndTokenRotationReregisters() async throws {
        let made = await make()
        let push = made.push
        let transport = made.transport
        let clock = made.clock
        await push.register(token: "fcm-1", preferences: NotificationPreferences())
        var muted = NotificationPreferences()
        muted.sound = false
        await push.preferencesDidChange(muted)
        await settle()
        await clock.advance(by: 0.5)
        await push.settle()
        #expect(await transport.count(registerRoute) == 1)
        #expect(try await body(transport)["soundEnabled"] as? Bool == false)

        await push.tokenDidChange("fcm-2")
        await settle()
        await clock.advance(by: 0.5)
        await push.settle()
        #expect(await transport.count(registerRoute) == 2)
        #expect(try await body(transport, 1)["pushToken"] as? String == "fcm-2")
    }

    @Test func pushSwitchedOffUnregisters() async {
        let made = await make()
        let push = made.push
        let transport = made.transport
        let clock = made.clock
        let store = made.store
        var off = NotificationPreferences()
        off.pushEnabled = false
        await push.register(token: "fcm-1", preferences: off)
        await settle()
        await clock.advance(by: 0.5)
        await push.settle()
        #expect(await transport.count(registerRoute) == 0)
        #expect(await transport.count(unregisterRoute) == 1)
        #expect(store.data(forKey: StorageKey.pushFingerprint) == nil)
    }

    @Test func transientFailuresRetry() async {
        let made = await make()
        let push = made.push
        let transport = made.transport
        let clock = made.clock
        let store = made.store
        await transport.enqueue(registerRoute, .status(503), .status(503))
        await push.register(token: "fcm-1", preferences: NotificationPreferences())
        await settle()
        await clock.advance(by: 0.5)
        #expect(await eventually { await transport.count(registerRoute) == 1 })
        await clock.advance(by: 2)
        #expect(await eventually { await transport.count(registerRoute) == 2 })
        await clock.advance(by: 4)
        await push.settle()
        #expect(await transport.count(registerRoute) == 3)
        #expect(store.data(forKey: StorageKey.pushFingerprint) != nil)
    }

    @Test func installIdIsStable() async {
        let made = await make()
        let push = made.push
        let first = await push.deviceId
        #expect(await push.deviceId == first)
    }

    @Test func signOutUnregistersAndForgetsTheToken() async {
        let made = await make()
        let push = made.push
        let transport = made.transport
        let clock = made.clock
        let store = made.store
        await push.register(token: "fcm-1", preferences: NotificationPreferences())
        await settle()
        await clock.advance(by: 0.5)
        await push.settle()
        await push.reset()
        #expect(await transport.count(unregisterRoute) == 1)
        #expect(store.data(forKey: StorageKey.pushFingerprint) == nil)
        await push.preferencesDidChange(NotificationPreferences())
        var changed = NotificationPreferences()
        changed.mentions = false
        await push.preferencesDidChange(changed)
        await settle()
        await clock.advance(by: 0.5)
        await push.settle()
        #expect(await transport.count(registerRoute) == 1)
    }
}

/// A push registration repository over a routing transport, with its clock and store.
struct PushRig {
    let push: LivePushRegistrationRepository
    let transport: RoutingTransport
    let clock: TestClock
    let store: InMemoryKeyValueStore
}
