import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Activity")
struct ActivityTests {
    private let route = "GET api/chat/recent-activity"

    private func make() async -> (LiveActivityRepository, RoutingTransport) {
        let transport = RoutingTransport()
        await transport.set(route, .fixture("rest-chat-recent-activity"))
        return (
            LiveActivityRepository(api: makeAPI(transport), store: InMemoryLocalStore(), clock: TestClock()),
            transport
        )
    }

    private func feed(_ repository: LiveActivityRepository) async -> Resource<ActivityFeed>? {
        await latest(repository.feed())
    }

    @Test func loadsNewestFirst() async {
        let (repository, _) = await make()
        #expect(await feed(repository)?.isLoadingWithoutValue == true)
        await repository.refresh()
        let value = await feed(repository)?.value
        #expect(value?.items.count == 3)
        #expect(value?.hasMore == false)
        #expect(value?.items.first?.createdAt ?? .distantPast >= value?.items.last?.createdAt ?? .distantPast)
    }

    @Test func emptyAndError() async {
        let (repository, transport) = await make()
        await transport.enqueue(route, .json(#"{"data":[]}"#), .status(502))
        await repository.refresh()
        #expect(await feed(repository)?.value?.items.isEmpty == true)
        await repository.refresh()
        #expect(await feed(repository)?.error == .server(statusCode: 502))
    }

    @Test func markReadRollsBackOnFailure() async {
        let (repository, transport) = await make()
        await repository.refresh()
        await transport.set("PUT api/chat/recent-activity/4411/read", .status(500))
        await #expect(throws: WaiveraError.self) { try await repository.markRead(activityId: 4411) }
        #expect(await feed(repository)?.value?.items.first { $0.id == 4411 }?.isRead == false)
        await transport.set("PUT api/chat/recent-activity/read-all", .ok)
        try? await repository.markAllRead()
        #expect(await feed(repository)?.value?.unreadCount == 0)
    }

    @Test func hubEventsApply() async throws {
        let (repository, _) = await make()
        await repository.refresh()
        await repository.handle(try hubEvent("hub-receive-chat-read-state"))
        let items = await feed(repository)?.value?.items ?? []
        #expect(items.filter(\.isRead).map(\.id).sorted() == [4410, 4411, 4412])
        await repository.handle(try hubEvent("hub-remove-chat-activity"))
        #expect(await feed(repository)?.value?.items.contains { $0.id == 4410 } == false)
        await repository.handle(try hubEvent("hub-receive-chat-activity"))
        // The live copy of 4411 replaces the cached one rather than duplicating it.
        #expect(await feed(repository)?.value?.items.map(\.id).sorted() == [4411, 4412])
    }
}

@Suite("Bookmarks")
struct BookmarksTests {
    private let primary = "GET api/chat/bookmarks"

    private func make() async -> (LiveBookmarksRepository, RoutingTransport, ChatHarness) {
        let harness = ChatHarness()
        await harness.begin()
        let repository = LiveBookmarksRepository(
            api: harness.api,
            context: SessionContext(user: alex),
            chat: harness.engine,
            clock: harness.clock
        )
        return (repository, harness.transport, harness)
    }

    @Test func primaryEndpoint() async {
        let (repository, transport, _) = await make()
        await transport.set(primary, .fixture("rest-chat-get-bookmarks"))
        await repository.refresh()
        let list = await latest(repository.bookmarks())?.value
        #expect(list?.bookmarks.map(\.id) == [9330])
        #expect(list?.usedFallback == false)
        #expect(list?.bookmarks.first?.destination.conversationId == 7)
    }

    @Test func fallbackWalksConversationsWhenThePrimaryFails() async {
        let (repository, transport, _) = await make()
        await transport.set(primary, .status(500))
        await transport.set("GET api/chat/my-conversations", .fixture("rest-chat-get-my-conversations"))
        await transport.set("GET api/chat/search/conversation/7", .fixture("rest-chat-search-conversation"))
        await transport.set("GET api/chat/search/conversation/11", .json(#"{"data":[]}"#))
        await transport.set("GET api/chat/search/conversation/14", .json(#"{"data":[]}"#))
        await repository.refresh()
        let resource = await latest(repository.bookmarks())
        #expect(resource?.value?.usedFallback == true)
        #expect(resource?.value?.bookmarks.isEmpty == false)
        #expect(resource?.phase == .loaded)
    }

    @Test func fallbackFailureReportsTheOriginalError() async {
        let (repository, transport, _) = await make()
        await transport.set(primary, .status(500))
        await transport.set("GET api/chat/my-conversations", .status(503))
        await repository.refresh()
        #expect(await latest(repository.bookmarks())?.error == .server(statusCode: 500))
    }

    @Test func togglePatchesTheTimeline() async throws {
        let (repository, transport, harness) = await make()
        await transport.set("GET api/chat/7/messages/pagination", jsonArray([message(9330)]))
        await transport.set("POST api/chat/message/9330/bookmark", .fixture("rest-chat-toggle-bookmark"))
        await harness.engine.open(conversationId: 7)
        #expect(try await repository.toggle(messageId: 9330, conversationId: 7))
        #expect(harness.engine.timelineCells.cell(7).current.value?.messages.first?.isBookmarked == true)
    }
}
