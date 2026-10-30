import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Environment")
struct EnvironmentTests {
    @Test func signInStartsEverythingAndSignOutUnregistersAndWipes() async throws {
        let transport = RoutingTransport()
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
        let realtime = FakeRealtime()
        let store = InMemoryLocalStore()
        let auth = FakeAuth()
        let environment = DataEnvironment.assemble(
            LiveServices(
                auth: auth,
                api: APIClient(baseURL: testBaseURL, transport: transport, tokens: auth),
                realtime: realtime,
                webBaseURL: nil,
                localStore: store,
                keyValueStore: InMemoryKeyValueStore(),
                connectivity: ManualConnectivity(),
                clock: TestClock()
            )
        )
        await environment.launch()
        #expect(
            await eventually {
                if case .signedIn = environment.session.currentState { return true }
                return false
            }
        )
        #expect(await eventually { realtime.log.starts == 1 })
        #expect(await eventually { await latest(environment.conversations.conversations())?.value?.count == 3 })

        await environment.session.signOut()
        #expect(await transport.count("POST api/mobile-push/unregister") == 1)
        #expect(realtime.log.stops == 1)
        #expect(await latest(environment.conversations.conversations())?.value == nil)
        #expect(await store.data(for: .conversations) == nil)
        #expect(auth.calls.last == "signOut")
    }
}
