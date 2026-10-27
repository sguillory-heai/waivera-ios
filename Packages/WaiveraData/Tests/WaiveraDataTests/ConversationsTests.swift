import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Conversations")
struct ConversationsTests {
    private let allRoute = "GET api/chat/all"

    private func inbox(_ harness: ChatHarness) -> Resource<[Conversation]> { harness.engine.conversationsCell.current }

    @Test func idleThenLoadingThenLoaded() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.begin()
        #expect(inbox(harness).isLoadingWithoutValue)
        await harness.engine.refresh()
        let resource = inbox(harness)
        #expect(resource.phase == .loaded)
        #expect(resource.value?.map(\.id) == [7, 41, 58])
        #expect(harness.engine.unreadCell.current == 4)
        #expect(resource.updatedAt == harness.clock.now)
    }

    @Test func emptyInbox() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .json(#"{"data":[],"success":true,"statusCode":200}"#))
        await harness.begin()
        await harness.engine.refresh()
        #expect(inbox(harness).isEmpty)
        #expect(harness.engine.unreadCell.current == 0)
    }

    @Test func errorKeepsTheCachedRows() async {
        let harness = ChatHarness()
        await harness.transport.enqueue(allRoute, .fixture("rest-chat-get-all"), .status(500))
        await harness.begin()
        await harness.engine.refresh()
        await harness.engine.refresh()
        let resource = inbox(harness)
        #expect(resource.error == .server(statusCode: 500))
        #expect(resource.value?.count == 3)
    }

    @Test func offlineFailureIsTransient() async {
        let harness = ChatHarness()
        await harness.transport.setOffline(true)
        await harness.begin()
        await harness.engine.refresh()
        #expect(inbox(harness).error == .offline)
        #expect(inbox(harness).value == nil)
    }

    @Test func cachedInboxRendersBeforeTheNetwork() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.begin()
        await harness.engine.refresh()
        await harness.engine.flushPersistence()

        let next = ChatEngine(
            api: harness.api,
            realtime: harness.realtime,
            store: harness.store,
            clock: harness.clock,
            presence: ChatPresence()
        )
        await next.begin(user: alex)
        #expect(next.conversationsCell.current.value?.count == 3)
        #expect(next.conversationsCell.current.updatedAt == nil)
    }

    @Test func concurrentRefreshesShareOneRequest() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.begin()
        async let first: Void = harness.engine.refresh()
        async let second: Void = harness.engine.refresh()
        _ = await (first, second)
        #expect(await harness.transport.count(allRoute) == 1)
    }

    @Test func incomingMessageBumpsUnreadAndPreview() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.begin()
        await harness.engine.refresh()
        await harness.engine.handle(.message(message(9400, in: 41, text: "shift swap?", at: 1_792_600_000)))
        let row = inbox(harness).value?.first
        #expect(row?.id == 41)
        #expect(row?.unreadCount == 4)
        #expect(row?.preview == .text("shift swap?"))
        #expect(harness.engine.unreadCell.current == 5)
    }

    @Test func ownMessagesAndTheVisibleConversationDoNotCountUnread() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.transport.set("GET api/chat/7/messages/pagination", .fixture("rest-chat-get-messages-pagination"))
        await harness.transport.set("PUT api/chat/7/read-through", .fixture("rest-chat-read-through"))
        await harness.transport.set("POST api/chat/7/mark-as-read", .ok)
        await harness.begin()
        await harness.engine.refresh()
        await harness.engine.handle(.message(message(9401, in: 41, author: viewerId, text: "mine")))
        #expect(inbox(harness).value?.first { $0.id == 41 }?.unreadCount == 3)

        await harness.engine.open(conversationId: 7)
        await harness.engine.handle(.message(message(9402, in: 7, text: "on screen", at: 1_792_600_000)))
        #expect(inbox(harness).value?.first { $0.id == 7 }?.unreadCount == 0)
    }

    @Test func sparseEventNeverErasesThePreviewAndRefetches() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.begin()
        await harness.engine.refresh()
        let before = inbox(harness).value?.first { $0.id == 7 }?.preview
        await harness.engine.handle(.message(message(9312, in: 7, text: nil)))
        #expect(inbox(harness).value?.first { $0.id == 7 }?.preview == before)
        #expect(await eventually { await harness.transport.count(allRoute) >= 2 })
    }

    @Test func blankPreviewsAreHydratedKeepingTheListUnreadCount() async throws {
        let harness = ChatHarness()
        // The first row's preview arrives blank (gap G-05).
        var root = try #require(JSONSerialization.jsonObject(with: Fixture.data("rest-chat-get-all")) as? [String: Any])
        var rows = try #require(root["data"] as? [[String: Any]])
        var last = try #require(rows[0]["lastMessage"] as? [String: Any])
        for key in ["messageContent", "messagePlaintext", "messageDoc", "parsedMessageDoc"] { last[key] = nil }
        rows[0]["lastMessage"] = last
        root["data"] = rows
        let body = try JSONSerialization.data(withJSONObject: root)
        await harness.transport.set(allRoute, RoutingTransport.Reply(status: 200, body: body))
        await harness.transport.set("GET api/chat/conversation/7", .fixture("rest-chat-get-conversation"))
        await harness.begin()
        await harness.engine.refresh()
        let row = inbox(harness).value?.first { $0.id == 7 }
        #expect(row?.preview.needsHydration == false)
        #expect(row?.unreadCount == 1)
        #expect(await harness.transport.count("GET api/chat/conversation/7") == 1)
    }

    @Test func callStateFollowsTheHub() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.begin()
        await harness.engine.refresh()
        await harness.engine.handle(
            .callStateChanged(CallStateChangedEvent(conversationId: 7, roomId: "room-1", status: .active))
        )
        #expect(inbox(harness).value?.first { $0.id == 7 }?.activeCall?.roomId == "room-1")
        await harness.engine.handle(.adHocRemoved(RemoveAdHocEvent(conversationId: 7, roomId: "room-1")))
        #expect(inbox(harness).value?.first { $0.id == 7 }?.activeCall == nil)
    }

    @Test func reconnectResyncRefetchesTheInbox() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.begin()
        await harness.engine.refresh()
        await harness.engine.resync()
        #expect(await harness.transport.count(allRoute) == 2)
        #expect(inbox(harness).phase == .loaded)
    }

    @Test func signOutClearsEverything() async {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.begin()
        await harness.engine.refresh()
        await harness.engine.end()
        #expect(inbox(harness).value == nil)
        #expect(harness.engine.unreadCell.current == 0)
    }

    @Test func leaveRemovesTheRow() async throws {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.transport.set("DELETE api/chat/delete/conversation/41", .fixture("rest-chat-leave-conversation"))
        await harness.begin()
        await harness.engine.refresh()
        try await harness.engine.leave(conversationId: 41)
        #expect(inbox(harness).value?.map(\.id) == [7, 58])
    }
}
