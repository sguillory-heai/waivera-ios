import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Messages")
struct MessagesTests {
    private let pageRoute = "GET api/chat/7/messages/pagination"

    private func timeline(_ harness: ChatHarness, _ id: Int = 7) -> Resource<MessageTimeline> {
        harness.engine.timelineCells.cell(id).current
    }

    private func page(_ ids: ClosedRange<Int>) -> RoutingTransport.Reply {
        jsonArray(ids.reversed().map { message($0, at: 1_792_400_000 + Double($0)) })
    }

    private func prepared() async -> ChatHarness {
        let harness = ChatHarness()
        await harness.transport.set("PUT api/chat/7/read-through", .fixture("rest-chat-read-through"))
        await harness.transport.set("POST api/chat/7/mark-as-read", .ok)
        await harness.begin()
        return harness
    }

    @Test func openJoinsLoadsAndMarksVisible() async {
        let harness = await prepared()
        await harness.transport.set(pageRoute, .fixture("rest-chat-get-messages-pagination-with-reaction"))
        #expect(timeline(harness).isLoadingWithoutValue)
        await harness.engine.open(conversationId: 7)
        #expect(harness.realtime.log.joins == [7])
        #expect(harness.presence.isActive(7))
        let resource = timeline(harness)
        #expect(resource.phase == .loaded)
        #expect(resource.value?.messages.map(\.id) == [9340])
        #expect(resource.value?.hasOlder == false)
        await harness.engine.close(conversationId: 7)
        #expect(harness.realtime.log.leaves == [7])
        #expect(!harness.presence.isActive(7))
    }

    @Test func emptyConversation() async {
        let harness = await prepared()
        await harness.transport.set(pageRoute, .fixture("rest-chat-get-messages-pagination-empty"))
        await harness.engine.open(conversationId: 7)
        #expect(timeline(harness).value?.isEmpty == true)
        #expect(timeline(harness).phase == .loaded)
    }

    @Test func errorState() async {
        let harness = await prepared()
        await harness.transport.set(pageRoute, .status(403))
        await harness.engine.open(conversationId: 7)
        #expect(timeline(harness).error == .forbidden)
        #expect(timeline(harness).value == nil)
    }

    @Test func threadRepliesStayOutOfTheTimeline() async {
        let harness = await prepared()
        await harness.transport.set(pageRoute, .fixture("rest-chat-get-messages-pagination-reply"))
        await harness.engine.open(conversationId: 7)
        #expect(timeline(harness).value?.messages.map(\.id) == [9330])
        let thread = harness.engine.threadCells.cell(9330).current.value
        #expect(thread?.replies.map(\.id) == [9331, 9332])
    }

    @Test func pagingStopsOnAShortPage() async {
        let harness = await prepared()
        await harness.transport.enqueue(pageRoute, page(51...100), page(1...50), page(1...1))
        await harness.engine.open(conversationId: 7)
        #expect(timeline(harness).value?.hasOlder == true)
        await harness.engine.loadOlder(conversationId: 7)
        #expect(timeline(harness).value?.messages.count == 100)
        #expect(timeline(harness).value?.hasOlder == true)
        // The second older page overlaps and does not move the cursor: stop (gap G-06).
        await harness.engine.loadOlder(conversationId: 7)
        #expect(timeline(harness).value?.hasOlder == false)
        await harness.engine.loadOlder(conversationId: 7)
        #expect(await harness.transport.count(pageRoute) == 3)
    }

    @Test func olderPageFailureKeepsMessages() async {
        let harness = await prepared()
        await harness.transport.enqueue(pageRoute, page(51...100), .status(503))
        await harness.engine.open(conversationId: 7)
        await harness.engine.loadOlder(conversationId: 7)
        #expect(timeline(harness).error == .server(statusCode: 503))
        #expect(timeline(harness).value?.messages.count == 50)
        #expect(timeline(harness).value?.isLoadingOlder == false)
    }

    @Test func reconnectAfterAGapRestartsFromTheNewestPage() async {
        let harness = await prepared()
        await harness.transport.enqueue(pageRoute, page(1...50), page(200...249))
        await harness.engine.open(conversationId: 7)
        await harness.engine.resync()
        let messages = timeline(harness).value?.messages.map(\.id) ?? []
        #expect(messages.first == 200)
        #expect(messages.count == 50)
        #expect(timeline(harness).value?.hasOlder == true)
    }

    @Test func reconnectMergesAnOverlappingTail() async {
        let harness = await prepared()
        await harness.transport.enqueue(pageRoute, page(1...50), page(11...60))
        await harness.engine.open(conversationId: 7)
        await harness.engine.resync()
        #expect(timeline(harness).value?.messages.count == 60)
    }

    @Test func liveMessagesAppendInOrderWithoutDuplicates() async {
        let harness = await prepared()
        await harness.transport.set(pageRoute, page(1...3))
        await harness.engine.open(conversationId: 7)
        await harness.engine.handle(.message(message(5, at: 1_792_500_000)))
        await harness.engine.handle(.message(message(4, at: 1_792_499_000)))
        await harness.engine.handle(.message(message(5, at: 1_792_500_000)))
        #expect(timeline(harness).value?.messages.map(\.id) == [1, 2, 3, 4, 5])
    }

    @Test func unopenedConversationIgnoresLiveMessagesUntilOpened() async {
        let harness = await prepared()
        await harness.engine.handle(.message(message(5)))
        #expect(timeline(harness).value == nil)
    }

    @Test func editAndDeleteUpdateInPlace() async throws {
        let harness = await prepared()
        // The edit and delete fixtures are for message 9312.
        await harness.transport.set(pageRoute, jsonArray([message(9312, text: "can you cover Friday?")]))
        await harness.transport.set("PUT api/chat/message/9312", .fixture("rest-chat-edit-message"))
        await harness.transport.set("DELETE api/chat/message/9312", .fixture("rest-chat-delete-message"))
        await harness.engine.open(conversationId: 7)
        try await harness.engine.edit(messageId: 9312, conversationId: 7, text: "can you cover Saturday?")
        let edited = timeline(harness).value?.messages
        #expect(edited?.count == 1)
        #expect(edited?.first?.isEdited == true)
        #expect(edited?.first?.bodyText == "can you cover Saturday?")
        try await harness.engine.delete(messageId: 9312, conversationId: 7)
        let deleted = timeline(harness).value?.messages.first
        #expect(deleted?.isDeleted == true)
        #expect(deleted?.bodyText == nil)
    }

    @Test func markReadUsesTheHubThenReadsThroughOnce() async {
        let harness = await prepared()
        await harness.transport.set(pageRoute, page(1...3))
        await harness.engine.open(conversationId: 7)
        harness.realtime.connect()
        let readStates = harness.engine.readStates()
        await harness.engine.markRead(conversationId: 7)
        await harness.engine.markRead(conversationId: 7)
        #expect(harness.realtime.log.markAsRead == [7, 7])
        #expect(await harness.transport.count("POST api/chat/7/mark-as-read") == 0)
        #expect(await harness.transport.count("PUT api/chat/7/read-through") == 1)
        #expect(await latest(readStates) != nil)
    }

    @Test func markReadFallsBackToRestWhenDisconnected() async {
        let harness = await prepared()
        await harness.transport.set(pageRoute, page(1...3))
        await harness.engine.open(conversationId: 7)
        await harness.engine.markRead(conversationId: 7)
        #expect(await harness.transport.count("POST api/chat/7/mark-as-read") == 1)
    }
}

@Suite("Reactions")
struct ReactionTests {
    private func opened() async -> ChatHarness {
        let harness = ChatHarness()
        await harness.transport.set(
            "GET api/chat/7/messages/pagination",
            jsonArray([message(1, text: "hi")])
        )
        await harness.begin()
        await harness.engine.open(conversationId: 7)
        return harness
    }

    private func reactions(_ harness: ChatHarness) -> [Reaction] {
        harness.engine.timelineCells.cell(7).current.value?.messages.first?.reactions ?? []
    }

    @Test func toggleAddsReplacesAndRemoves() async throws {
        let harness = await opened()
        harness.realtime.connect()
        try await harness.engine.toggleReaction("👍", messageId: 1, conversationId: 7)
        #expect(reactions(harness).map(\.emoji) == ["👍"])
        try await harness.engine.toggleReaction("❤️", messageId: 1, conversationId: 7)
        #expect(reactions(harness).map(\.emoji) == ["❤️"])
        try await harness.engine.toggleReaction("❤️", messageId: 1, conversationId: 7)
        #expect(reactions(harness).isEmpty)
        #expect(harness.realtime.log.reactions.count == 3)
    }

    @Test func failureRollsBack() async {
        let harness = await opened()
        harness.realtime.connect()
        harness.realtime.reactionError.update { $0 = .forbidden }
        await #expect(throws: WaiveraError.forbidden) {
            try await harness.engine.toggleReaction("👍", messageId: 1, conversationId: 7)
        }
        #expect(reactions(harness).isEmpty)
    }

    @Test func unavailableWithoutTheHub() async {
        let harness = await opened()
        await #expect(throws: WaiveraError.realtimeUnavailable) {
            try await harness.engine.toggleReaction("👍", messageId: 1, conversationId: 7)
        }
        #expect(harness.realtime.log.reactions.isEmpty)
    }

    @Test func otherUsersReactionsArriveLive() async {
        let harness = await opened()
        await harness.engine.handle(
            .reaction(
                ReactionEvent(
                    conversationId: 7,
                    messageId: 1,
                    userId: "usr_priya_raman",
                    reactionType: "🎉",
                    action: .added
                )
            )
        )
        #expect(reactions(harness).map(\.userId) == ["usr_priya_raman"])
    }
}
