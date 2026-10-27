import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

/// Core additions the feature requests asked for (docs/requests/*.md) and the Android critic
/// findings that applied on iOS (docs/requests/critic-carryover.md).
@Suite("Chat requests and carry-over")
struct ChatCarryoverTests {
    private let allRoute = "GET api/chat/all"
    private let pageRoute = "GET api/chat/7/messages/pagination"
    private let sendRoute = "POST api/chat/send"

    private func timeline(_ harness: ChatHarness) -> Resource<MessageTimeline> {
        harness.engine.timelineCells.cell(7).current
    }

    private func page(_ ids: ClosedRange<Int>) -> RoutingTransport.Reply {
        jsonArray(ids.reversed().map { message($0, at: 1_792_400_000 + Double($0)) })
    }

    private func ascending(_ ids: ClosedRange<Int>) -> RoutingTransport.Reply {
        jsonArray(ids.map { message($0, at: 1_792_400_000 + Double($0)) })
    }

    private func unread(_ harness: ChatHarness, _ id: Int) -> Int? {
        harness.engine.conversationsCell.current.value?.first { $0.id == id }?.unreadCount
    }

    @Test("AF-08: a failed mark-as-read restores the unread count and throws")
    func markReadRollsBack() async throws {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.transport.set("POST api/chat/41/mark-as-read", .status(500))
        await harness.begin()
        await harness.engine.refresh()
        #expect(unread(harness, 41) == 3)
        await #expect(throws: WaiveraError.server(statusCode: 500)) {
            try await harness.engine.markRead(conversationId: 41)
        }
        #expect(unread(harness, 41) == 3)
        #expect(harness.engine.unreadCell.current == 4)

        await harness.transport.set("POST api/chat/41/mark-as-read", .ok)
        try await harness.engine.markRead(conversationId: 41)
        #expect(unread(harness, 41) == 0)
    }

    @Test("AF-10: an edit updates the inbox preview without waiting for the hub")
    func editUpdatesThePreview() async throws {
        let harness = ChatHarness()
        await harness.transport.set(allRoute, .fixture("rest-chat-get-all"))
        await harness.transport.set(pageRoute, jsonArray([message(9312, text: "can you cover Friday?")]))
        await harness.transport.set("PUT api/chat/message/9312", .fixture("rest-chat-edit-message"))
        await harness.begin()
        await harness.engine.refresh()
        await harness.engine.open(conversationId: 7)
        try await harness.engine.edit(messageId: 9312, conversationId: 7, text: "can you cover Saturday?")
        let row = harness.engine.conversationsCell.current.value?.first { $0.id == 7 }
        #expect(row?.lastMessage?.bodyText == "can you cover Saturday?")
        #expect(row?.lastMessage?.isEdited == true)
    }

    @Test("AF-02: a repeated echo with a confirmed client id never drops another queued message")
    func repeatedEchoKeepsTheOtherPendingMessage() async throws {
        let harness = ChatHarness()
        await harness.transport.set(pageRoute, jsonArray([message(1)]))
        await harness.begin()
        await harness.engine.open(conversationId: 7)
        await harness.transport.set(sendRoute, .status(400))
        let first = try #require(await harness.engine.send(text: "ok", attachment: nil, conversationId: 7))
        let second = try #require(await harness.engine.send(text: "ok", attachment: nil, conversationId: 7))
        let echo = message(600, author: viewerId, text: "ok", at: 1_792_500_000, clientId: first.clientMessageId)
        await harness.engine.handle(.message(echo))
        await harness.engine.handle(.message(echo))
        var duplicate = echo
        duplicate.id = 600
        await harness.engine.handle(.message(duplicate))
        #expect(timeline(harness).value?.pending.map(\.clientMessageId) == [second.clientMessageId])
    }

    @Test("AS-03: queued messages from another account are dropped, never sent")
    func outboxBelongsToItsAuthor() async throws {
        let harness = ChatHarness()
        await harness.transport.set(sendRoute, .fixture("rest-chat-send-message"))
        let mine = OutgoingMessage(
            clientMessageId: "mine",
            conversationId: 7,
            parentMessageId: nil,
            text: "mine",
            doc: nil,
            createdAt: harness.clock.now,
            state: .queued(attempt: 1),
            authorId: viewerId
        )
        var theirs = mine
        theirs.clientMessageId = "theirs"
        theirs.authorId = "usr_someone_else"
        var legacy = mine
        legacy.clientMessageId = "legacy"
        legacy.authorId = nil
        await harness.store.save([mine, theirs, legacy], for: .outbox)
        await harness.begin()
        #expect(await eventually { await harness.transport.count(sendRoute) == 1 })
        await settle()
        #expect(await harness.transport.count(sendRoute) == 1)
        let body = try #require(await harness.transport.bodies(sendRoute).first)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["clientMessageId"] as? String == "mine")
    }

    @Test("Conversation request 2: an older-page failure is reported on its own")
    func olderPageFailureKeepsThePhase() async {
        let harness = ChatHarness()
        await harness.transport.set(pageRoute, page(51...100))
        await harness.begin()
        await harness.engine.open(conversationId: 7)
        #expect(timeline(harness).value?.hasOlder == true)
        await harness.transport.set(pageRoute, .status(503))
        await harness.engine.loadOlder(conversationId: 7)
        #expect(timeline(harness).phase == .loaded)
        #expect(timeline(harness).value?.olderPageError == .server(statusCode: 503))
        await harness.transport.set(pageRoute, page(1...50))
        await harness.engine.loadOlder(conversationId: 7)
        #expect(timeline(harness).value?.olderPageError == nil)
        #expect(timeline(harness).value?.messages.count == 100)
    }

    @Test("AF-03: loading around an old message fills forward to the loaded rows, with no hole")
    func loadAroundLeavesNoGap() async throws {
        let harness = ChatHarness()
        await harness.transport.set(pageRoute, page(101...150))
        await harness.transport.set("GET api/chat/7/messages/context/10", ascending(1...85))
        await harness.transport.set("GET api/chat/7/messages/context/85", ascending(85...150))
        await harness.begin()
        await harness.engine.open(conversationId: 7)
        #expect(try await harness.engine.loadAround(conversationId: 7, messageId: 10))
        let ids = timeline(harness).value?.messages.map(\.id) ?? []
        #expect(ids == Array(1...150))
        #expect(timeline(harness).value?.hasOlder == false)
        #expect(await harness.transport.count("GET api/chat/7/messages/context/85") == 1)
    }

    @Test("Load around: a hole too long to close is not merged")
    func loadAroundGivesUpOnAnEndlessGap() async throws {
        let harness = ChatHarness()
        await harness.transport.set(pageRoute, page(5_001...5_050))
        await harness.transport.set("GET api/chat/7/messages/context/10", ascending(1...85))
        await harness.begin()
        await harness.engine.open(conversationId: 7)
        // Each forward page returns 75 newer messages that never reach id 5001.
        var cursor = 85
        for _ in 0..<ChatEngine.maxForwardPages {
            await harness.transport.set("GET api/chat/7/messages/context/\(cursor)", ascending(cursor...(cursor + 75)))
            cursor += 75
        }
        #expect(try await harness.engine.loadAround(conversationId: 7, messageId: 10) == false)
        #expect(timeline(harness).value?.messages.map(\.id) == Array(5_001...5_050))
    }

    @Test("Load around: a target already loaded makes no request")
    func loadAroundWithALoadedTarget() async throws {
        let harness = ChatHarness()
        await harness.transport.set(pageRoute, page(1...20))
        await harness.begin()
        await harness.engine.open(conversationId: 7)
        #expect(try await harness.engine.loadAround(conversationId: 7, messageId: 5))
        #expect(await harness.transport.requests.filter { $0.url?.path.contains("context") == true }.isEmpty)
    }

    @Test("Sort fallback: a live call's start orders a conversation without messages")
    func callStartIsASortFallback() {
        var quiet = Conversation(id: 1, kind: .group, viewerId: viewerId)
        quiet.lastReadAt = Date(timeIntervalSince1970: 100)
        var calling = Conversation(id: 2, kind: .group, viewerId: viewerId)
        calling.activeCall = CallRoom(roomId: "r", startedAt: Date(timeIntervalSince1970: 200))
        #expect(calling.activityDate == Date(timeIntervalSince1970: 200))
        #expect(ChatEngine.inboxOrder(calling, quiet))
    }
}

@Suite("Activity requests")
struct ActivityRequestTests {
    private let route = "GET api/chat/recent-activity"

    private func fullPage(startingAt first: Int64) -> RoutingTransport.Reply {
        let rows = (0..<Int64(LiveActivityRepository.pageSize)).map { offset in
            let id = first + offset
            return #"{"id":\#(id),"activityType":"chat.mention","conversationId":7,"messageId":\#(id),"#
                + #""read":false,"createdAt":"2026-10-2\#(offset % 9)T10:00:00Z"}"#
        }
        return .json("[" + rows.joined(separator: ",") + "]")
    }

    @Test("Today request 4: a failed page keeps the feed loaded and Retry fetches just that page")
    func loadMoreFailureIsSeparate() async {
        let transport = RoutingTransport()
        await transport.enqueue(route, fullPage(startingAt: 1), .status(500), .json("[]"))
        let repository = LiveActivityRepository(
            api: makeAPI(transport),
            store: InMemoryLocalStore(),
            clock: TestClock()
        )
        await repository.refresh()
        #expect(await latest(repository.feed())?.value?.hasMore == true)
        await repository.loadMore()
        var resource = await latest(repository.feed())
        #expect(resource?.phase == .loaded)
        #expect(resource?.value?.loadMoreError == .server(statusCode: 500))
        #expect(resource?.value?.items.count == LiveActivityRepository.pageSize)
        await repository.loadMore()
        resource = await latest(repository.feed())
        #expect(resource?.value?.loadMoreError == nil)
        #expect(resource?.value?.hasMore == false)
        let pages = await transport.requests.compactMap { $0.url?.query }.filter { $0.contains("page=") }
        #expect(pages.filter { $0.contains("page=2") }.count == 2)
        #expect(pages.filter { $0.contains("page=1&") || $0.hasPrefix("page=1") }.count == 1)
    }

    @Test("Activity paging runs one page at a time")
    func loadMoreIsSerialized() async {
        let transport = RoutingTransport()
        await transport.enqueue(route, fullPage(startingAt: 1), .json("[]"), .json("[]"))
        let repository = LiveActivityRepository(
            api: makeAPI(transport),
            store: InMemoryLocalStore(),
            clock: TestClock()
        )
        await repository.refresh()
        async let first: Void = repository.loadMore()
        async let second: Void = repository.loadMore()
        _ = await (first, second)
        #expect(await transport.count(route) == 2)
    }
}

@Suite("Calendar requests")
struct CalendarRequestTests {
    private let feedRoute = "GET api/CalendarEvent/GetAllEvent"

    private func repository(user: CurrentUser? = alex) -> (LiveCalendarRepository, RoutingTransport) {
        let transport = RoutingTransport()
        let api = APIClient(baseURL: testBaseURL, transport: transport, tokens: FakeAuth())
        let repository = LiveCalendarRepository(
            api: api,
            context: SessionContext(user: user),
            store: InMemoryLocalStore(),
            clock: TestClock(),
            handoff: WebCallHandoff(webBaseURL: URL(string: "https://web.example.test"), api: api)
        )
        return (repository, transport)
    }

    @Test("Schedule request 1: one event by id from GetEventbyId, and 404 as not found")
    func singleEventLookup() async throws {
        let (repository, transport) = repository()
        let body =
            #"{"data":{"id":"evt_solo","title":"1:1","startTime":"2026-11-03T15:00:00","#
            + #""endTime":"2026-11-03T15:30:00","ownerUserID":"usr_alex_rivera"},"statusCode":200}"#
        await transport.set("GET api/CalendarEvent/GetEventbyId/evt_solo", .json(body))
        await transport.set("GET api/CalendarEvent/GetEventbyId/evt_gone", .status(404))
        await repository.refreshEvent(id: "evt_solo")
        let found = try #require(await latest(repository.event(id: "evt_solo")))
        #expect(found.value?.event?.title == "1:1")
        #expect(found.value?.event?.isOwner == true)
        #expect(found.value?.event?.start == utc(2026, 11, 3, 15))
        await repository.refreshEvent(id: "evt_gone")
        #expect(await latest(repository.event(id: "evt_gone"))?.value == .notFound)
    }

    @Test("Single event: a loaded feed answers first and keeps an open lookup current")
    func feedCopyFeedsTheLookup() async throws {
        let (repository, transport) = repository()
        await transport.set(feedRoute, .fixture("rest-calendar-get-all-event"))
        await transport.set("GET api/CalendarEvent/GetEventbyId/evt_8f2b19c4", .status(500))
        _ = repository.event(id: "evt_8f2b19c4")
        await repository.refresh(period: .month, containing: date(2026, 10, 20))
        #expect(await latest(repository.event(id: "evt_8f2b19c4"))?.value?.event?.id == "evt_8f2b19c4")
        await repository.refreshEvent(id: "evt_8f2b19c4")
        let resource = await latest(repository.event(id: "evt_8f2b19c4"))
        #expect(resource?.error == .server(statusCode: 500))
        #expect(resource?.value?.event != nil)
        await transport.set("POST api/invitation/AcceptDenyMeeting", .fixture("rest-invitation-accept-deny-meeting"))
        try await repository.respond(toEventId: "evt_8f2b19c4", accept: false)
        #expect(await latest(repository.event(id: "evt_8f2b19c4"))?.value?.event?.viewerResponse == .declined)
    }

    @Test("Single event: a recurring occurrence is found through its own month")
    func occurrenceLookupUsesItsMonth() async throws {
        let (repository, transport) = repository()
        await transport.set(feedRoute, .json(#"{"data":{"events":[],"timeOff":[],"holidays":[]}}"#))
        let id = "aca5f915-7ca4-4366-9e9c-7886d5dc41fc-2026-05-02T14:00:00.000Z"
        #expect(CalendarEvent.occurrenceInstant(fromId: id) == utc(2026, 5, 2, 14))
        #expect(CalendarEvent.occurrenceInstant(fromId: "evt_solo") == nil)
        await repository.refreshEvent(id: id)
        #expect(await latest(repository.event(id: id))?.value == .notFound)
        let query = await transport.requests.first?.url?.query ?? ""
        // The May 2026 grid starts Sunday 26 April in Chicago (05:00Z, CDT).
        #expect(query.contains("2026-04-26T05:00:00"))
        #expect(await transport.count("GET api/CalendarEvent/GetEventbyId/\(id)") == 0)
    }

    @Test("Today request 2: a reconnect refetches every observed feed and milestones")
    func refreshObservedRefetchesFeeds() async {
        let (repository, transport) = repository()
        await transport.set(feedRoute, .fixture("rest-calendar-get-all-event"))
        await transport.set("GET api/CalendarEvent/milestones", .fixture("rest-calendar-get-milestones"))
        await repository.refresh(period: .week, containing: date(2026, 10, 20))
        await repository.refresh(period: .week, containing: date(2026, 10, 27))
        await repository.refreshObserved()
        #expect(await transport.count(feedRoute) == 4)
        #expect(await transport.count("GET api/CalendarEvent/milestones") == 1)
    }

    @Test(
        "Schedule request 2: a missing, invalid or fixed-offset zone falls back to America/Chicago",
        arguments: [nil, "", "Not/AZone", "GMT-6", "CST", "Etc/GMT+6", "+05:00"]
    )
    func fallbackZone(identifier: String?) {
        var user = alex
        user.timeZoneIdentifier = identifier
        #expect(user.scheduleTimeZone.identifier == "America/Chicago")
        #expect(user.isUsingFallbackTimeZone)
        let (repository, _) = repository(user: user)
        #expect(repository.scheduleTimeZone().isFallback)
    }

    @Test("A named zone is kept, including across its DST change")
    func namedZoneIsKept() throws {
        var user = alex
        user.timeZoneIdentifier = "America/Denver"
        #expect(user.scheduleTimeZone.identifier == "America/Denver")
        #expect(!user.isUsingFallbackTimeZone)
        // Denver falls back on 1 November 2026: that day is 25 hours long.
        #expect(date(2026, 11, 1).interval(in: user.scheduleTimeZone).duration == 25 * 3_600)
    }
}
