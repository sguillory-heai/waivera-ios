import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures

@testable import WaiveraData

/// Fixes from the iOS port security review (PS-01).
@Suite("Port security fixes")
struct PortSecurityTests {
    private let route = "GET api/chat/privatechats/usr_priya_raman/conversation"

    private let sam = CurrentUser(
        id: "usr_sam_ortiz",
        firebaseUid: "fb-sam",
        email: "sam.ortiz@example.com",
        firstName: "Sam",
        lastName: "Ortiz",
        timeZoneIdentifier: "America/Chicago"
    )

    private func inboxIds(_ harness: ChatHarness) -> [Int] {
        harness.engine.conversationsCell.current.value?.map(\.id) ?? []
    }

    @Test("PS-01: a direct chat that opens after an account switch stays out of the next inbox")
    func aLateOpenAfterAnAccountSwitchIsDropped() async throws {
        let harness = ChatHarness()
        let gate = Gate()
        let route = route
        await harness.transport.set(route, .fixture("rest-chat-create-conversation-existing"))
        await harness.transport.setBeforeReply { request in
            if RoutingTransport.route(of: request) == route { await gate.wait() }
        }
        await harness.begin()
        let engine = harness.engine
        let open = Task { try await engine.openDirectConversation(with: "usr_priya_raman") }
        #expect(await eventually { await harness.transport.count(route) == 1 })

        await harness.engine.end()
        await harness.engine.begin(user: sam)
        await gate.open()

        await #expect(throws: WaiveraError.signedOut) { try await open.value }
        #expect(!inboxIds(harness).contains(7))
        await harness.engine.flushPersistence()
        let saved = await harness.store.load([Conversation].self, for: .conversations) ?? []
        #expect(!saved.contains { $0.id == 7 })
    }

    @Test("PS-01: a chat the signed-in person is not in is never cached")
    func aChatWithoutTheViewerIsNotCached() async throws {
        let harness = ChatHarness()
        await harness.transport.set(route, .fixture("rest-chat-create-conversation-existing"))
        await harness.engine.begin(user: sam)
        await #expect(throws: WaiveraError.invalidResponse) {
            _ = try await harness.engine.openDirectConversation(with: "usr_priya_raman")
        }
        #expect(!inboxIds(harness).contains(7))
    }

    @Test("PS-01: the same open for the person who asked still lands")
    func anOpenThatFinishesInTheSameSessionLands() async throws {
        let harness = ChatHarness()
        await harness.transport.set(route, .fixture("rest-chat-create-conversation-existing"))
        await harness.begin()
        let conversation = try await harness.engine.openDirectConversation(with: "usr_priya_raman")
        #expect(conversation.id == 7)
        #expect(inboxIds(harness).contains(7))
    }
}
