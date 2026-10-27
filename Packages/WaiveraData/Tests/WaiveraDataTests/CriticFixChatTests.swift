import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

/// Chat fixes for the iOS functional review (IF-01 to IF-04, IF-07).
@Suite("Critic fixes: chat")
struct CriticFixChatTests {
    private let pageRoute = "GET api/chat/7/messages/pagination"
    private let sendRoute = "POST api/chat/send"

    private func page(_ ids: ClosedRange<Int>) -> RoutingTransport.Reply {
        jsonArray(ids.reversed().map { message($0, at: 1_792_400_000 + Double($0)) })
    }

    private func timeline(_ harness: ChatHarness) -> MessageTimeline? {
        harness.engine.timelineCells.cell(7).current.value
    }

    private func prepared() async -> ChatHarness {
        let harness = ChatHarness()
        await harness.transport.set("PUT api/chat/7/read-through", .fixture("rest-chat-read-through"))
        await harness.transport.set("POST api/chat/7/mark-as-read", .ok)
        await harness.begin()
        return harness
    }

    // MARK: IF-01

    @Test("IF-01: a live message that lands before the newest page does not hide the gap")
    func liveMessageBeforeTheNewestPageStillPagesTheGap() async {
        let harness = await prepared()
        await harness.transport.enqueue(
            pageRoute,
            page(1...50),
            // After the reconnect: the newest page, then older pages back to message 50.
            page(251...300),
            page(201...250),
            page(151...200),
            page(101...150),
            page(51...100),
            page(1...50)
        )
        await harness.engine.open(conversationId: 7)
        harness.realtime.drop()
        // The hub delivers message 300 live before the newest-page fetch returns.
        await harness.engine.handle(.message(message(300, at: 1_792_400_300)))
        await harness.engine.resync()
        let ids = timeline(harness)?.messages.map(\.id) ?? []
        #expect(ids == Array(1...300))
        #expect(timeline(harness)?.hasOlder == true)
    }

    @Test("IF-01: a gap too long to page restarts from the newest pages with hasOlder")
    func aGapTooLongRestartsTheTimeline() async {
        let harness = await prepared()
        await harness.transport.enqueue(
            pageRoute,
            page(1...50),
            page(551...600),
            page(501...550),
            page(451...500),
            page(401...450),
            page(351...400),
            page(301...350)
        )
        await harness.engine.open(conversationId: 7)
        await harness.engine.handle(.message(message(600, at: 1_792_400_600)))
        await harness.engine.resync()
        let ids = timeline(harness)?.messages.map(\.id) ?? []
        #expect(ids == Array(301...600))
        #expect(timeline(harness)?.hasOlder == true)
        // Paging back continues from the oldest fetched row, so the skipped range is reachable.
        await harness.transport.enqueue(pageRoute, page(251...300))
        await harness.engine.loadOlder(conversationId: 7)
        #expect(timeline(harness)?.messages.first?.id == 251)
    }

    @Test("IF-01: a closed conversation that got a live message pages its gap when reopened")
    func aClosedConversationPagesItsGapOnReopen() async {
        let harness = await prepared()
        await harness.transport.enqueue(pageRoute, page(1...50), page(81...130), page(31...80))
        await harness.engine.open(conversationId: 7)
        await harness.engine.close(conversationId: 7)
        await harness.engine.handle(.message(message(130, at: 1_792_400_130)))
        await harness.engine.open(conversationId: 7)
        #expect(timeline(harness)?.messages.map(\.id) == Array(1...130))
    }

    @Test("IF-01: after a reconnect a closed conversation's cache takes no live rows until reopened")
    func aReconnectMarksClosedConversationsStale() async {
        let harness = await prepared()
        await harness.transport.enqueue(pageRoute, page(1...50))
        await harness.engine.open(conversationId: 7)
        await harness.engine.close(conversationId: 7)
        await harness.engine.resync()
        await harness.engine.handle(.message(message(400, at: 1_792_400_400)))
        #expect(timeline(harness)?.messages.map(\.id) == Array(1...50))
    }

    @Test("IF-01: the disk cache holds only synced rows")
    func diskCacheHoldsOnlySyncedRows() async {
        let harness = await prepared()
        await harness.transport.enqueue(pageRoute, page(1...50))
        await harness.engine.open(conversationId: 7)
        await harness.engine.handle(.message(message(90, at: 1_792_400_090)))
        await harness.engine.flushPersistence()
        let cached = await harness.store.load([ChatMessage].self, for: .messages(7)) ?? []
        #expect(cached.map(\.id).max() == 50)
    }

    // MARK: IF-02

    private func threadHarness() async -> (ChatHarness, LiveChatAlertsRepository) {
        let harness = ChatHarness()
        await harness.transport.set(pageRoute, .fixture("rest-chat-get-messages-pagination-reply"))
        await harness.transport.set("GET api/chat/thread/9330", .fixture("rest-chat-get-thread"))
        await harness.transport.set("GET api/chat/all", .fixture("rest-chat-get-all"))
        await harness.transport.set("PUT api/chat/7/read-through", .fixture("rest-chat-read-through"))
        await harness.transport.set("POST api/chat/7/mark-as-read", .ok)
        await harness.begin()
        await harness.engine.refresh()
        harness.realtime.connect()
        let alerts = LiveChatAlertsRepository(
            chat: harness.engine,
            presence: harness.presence,
            realtime: harness.realtime
        )
        return (harness, alerts)
    }

    private func unread(_ harness: ChatHarness) -> Int? {
        harness.engine.conversationsCell.current.value?.first { $0.id == 7 }?.unreadCount
    }

    @Test("IF-02: with only a thread open, a main-timeline message is unread and alerts")
    func aThreadDoesNotMakeItsConversationVisible() async {
        let (harness, alerts) = await threadHarness()
        await harness.engine.open(rootMessageId: 9330, conversationId: 7)
        let before = unread(harness) ?? 0
        await harness.engine.handle(.message(message(9600, text: "@Alex in the channel", at: 1_792_600_000)))
        #expect(unread(harness) == before + 1)
        #expect(harness.realtime.log.markAsRead.isEmpty)
        #expect(await harness.transport.count("POST api/chat/7/mark-as-read") == 0)
        #expect(alerts.shouldPresentForegroundPush(conversationId: 7, threadRootMessageId: nil))
    }

    @Test("IF-02: a reply in the open thread is read there and its push is hidden")
    func aReplyInTheOpenThreadIsRead() async throws {
        let (harness, alerts) = await threadHarness()
        await harness.engine.open(rootMessageId: 9330, conversationId: 7)
        let before = unread(harness) ?? 0
        await harness.engine.handle(.message(message(9601, text: "reply", at: 1_792_600_000, parent: 9330)))
        #expect(unread(harness) == before)
        let body = try #require(await harness.transport.bodies("PUT api/chat/7/read-through").last)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["threadRootMessageId"] as? Int == 9330)
        #expect(!alerts.shouldPresentForegroundPush(conversationId: 7, threadRootMessageId: 9330))
        // A reply in another thread of the same conversation still shows.
        #expect(alerts.shouldPresentForegroundPush(conversationId: 7, threadRootMessageId: 9999))
    }

    // MARK: IF-03

    @Test("IF-03: sendAndWait returns after the send, and the outbox was on disk before it")
    func sendAndWaitIsDurable() async throws {
        let transport = RoutingTransport()
        let store = SlowStore()
        let clock = TestClock()
        let engine = ChatEngine(
            api: makeAPI(transport),
            realtime: FakeRealtime(),
            store: store,
            clock: clock,
            presence: ChatPresence()
        )
        await transport.set(sendRoute, .fixture("rest-chat-send-message"))
        let onDiskAtSend = LockedValue<Int?>(nil)
        await transport.setBeforeReply { _ in
            let saved = await store.load([OutgoingMessage].self, for: .outbox)
            onDiskAtSend.update { $0 = saved?.count }
        }
        await engine.begin(user: alex)
        let outcome = await engine.sendAndWait(
            text: "On my way",
            conversationId: 7,
            threadRootMessageId: nil,
            timeout: .seconds(20)
        )
        #expect(outcome == .sent)
        #expect(await transport.count(sendRoute) == 1)
        #expect(onDiskAtSend.get() == 1)
    }

    @Test("IF-03: a reply that cannot go out in time stays queued on disk")
    func sendAndWaitTimesOutQueued() async throws {
        let harness = await prepared()
        await harness.transport.setOffline(true)
        let waiting = Task {
            await harness.engine.sendAndWait(
                text: "On my way",
                conversationId: 7,
                threadRootMessageId: 9330,
                timeout: .seconds(20)
            )
        }
        #expect(await eventually { await harness.transport.count(sendRoute) >= 1 })
        // The reply's timeout and the offline backoff are both waiting on the clock.
        #expect(await eventually { harness.clock.pendingSleepers >= 2 })
        await harness.clock.advance(by: 21)
        #expect(await waiting.value == .queued)
        let saved = await harness.store.load([OutgoingMessage].self, for: .outbox) ?? []
        #expect(saved.map(\.parentMessageId) == [9330])
    }

    @Test("IF-03: a reply the server refuses reports the failure")
    func sendAndWaitReportsAFailure() async {
        let harness = await prepared()
        await harness.transport.set(sendRoute, .status(403))
        let outcome = await harness.engine.sendAndWait(
            text: "nope",
            conversationId: 7,
            threadRootMessageId: nil,
            timeout: .seconds(20)
        )
        #expect(outcome == .failed(.forbidden))
    }

    // MARK: IF-04

    @Test("IF-04: offline sends stay queued with backoff and go out when the network returns")
    func offlineSendsStayQueued() async throws {
        let harness = await prepared()
        await harness.transport.setOffline(true)
        _ = try #require(await harness.engine.send(text: "basement", attachment: nil, conversationId: 7))
        for expected in 2...6 {
            #expect(await eventually { await harness.transport.count(sendRoute) == expected - 1 })
            await harness.clock.advance(by: 60)
        }
        #expect(await eventually { await harness.transport.count(sendRoute) >= 6 })
        #expect(timeline(harness)?.pending.first?.isFailed == false)
        await harness.transport.setOffline(false)
        await harness.transport.set(sendRoute, .fixture("rest-chat-send-message"))
        await harness.engine.resumeOutbox()
        #expect(await eventually { timeline(harness)?.pending.isEmpty == true })
    }

    @Test("IF-04: the offline backoff doubles and is capped")
    func offlineBackoffIsCapped() {
        #expect(ChatEngine.offlineBackoff(afterTries: 1) == .seconds(1))
        #expect(ChatEngine.offlineBackoff(afterTries: 3) == .seconds(4))
        #expect(ChatEngine.offlineBackoff(afterTries: 12) == ChatEngine.maxOfflineBackoff)
    }

    @Test("IF-04: a send that failed on a 5xx is retried on resume, Retry stays until then")
    func failedTransientSendsResume() async throws {
        let harness = await prepared()
        await harness.transport.set(sendRoute, .status(503))
        _ = try #require(await harness.engine.send(text: "outage", attachment: nil, conversationId: 7))
        #expect(await eventually { await harness.transport.count(sendRoute) == 1 })
        await harness.clock.advance(by: 1)
        #expect(await eventually { await harness.transport.count(sendRoute) == 2 })
        await harness.clock.advance(by: 2)
        #expect(await eventually { timeline(harness)?.pending.first?.isFailed == true })
        await harness.transport.set(sendRoute, .fixture("rest-chat-send-message"))
        await harness.engine.foregroundChanged(true)
        #expect(await eventually { timeline(harness)?.pending.isEmpty == true })
    }

    @Test("IF-04: a 400 fails at once and is not resumed")
    func badRequestFailsAtOnce() async throws {
        let harness = await prepared()
        await harness.transport.set(sendRoute, .status(400))
        _ = try #require(await harness.engine.send(text: "bad", attachment: nil, conversationId: 7))
        #expect(await eventually { timeline(harness)?.pending.first?.state == .failed(.invalidRequest) })
        await harness.engine.resumeOutbox()
        await settle()
        #expect(await harness.transport.count(sendRoute) == 1)
    }

    // MARK: IF-07

    @Test("IF-07: opening, marking read and reading elsewhere report the conversation read")
    func readsAreReported() async {
        let harness = await prepared()
        await harness.transport.set(pageRoute, page(1...3))
        let reads = LockedValue<[Int]>([])
        let stream = harness.engine.conversationsRead()
        let collector = Task { for await id in stream { reads.update { $0.append(id) } } }
        defer { collector.cancel() }
        await settle()
        await harness.engine.open(conversationId: 7)
        try? await harness.engine.markRead(conversationId: 7)
        await harness.engine.handle(
            .readReceipt(ReadReceiptEvent(conversationId: 41, userId: viewerId, lastReadAt: nil))
        )
        await harness.engine.handle(
            .readReceipt(ReadReceiptEvent(conversationId: 42, userId: "usr_priya_raman", lastReadAt: nil))
        )
        #expect(await eventually { reads.get() == [7, 7, 41] })
    }
}

/// A cache whose writes take a while, so a send that does not wait for the write would reach
/// the network first.
actor SlowStore: LocalStore {
    private let inner = InMemoryLocalStore()

    func data(for key: CacheKey) async -> Data? { await inner.data(for: key) }

    func store(_ data: Data, for key: CacheKey) async {
        try? await Task.sleep(for: .milliseconds(40))
        await inner.store(data, for: key)
    }

    func remove(_ key: CacheKey) async { await inner.remove(key) }
    func removeAll() async { await inner.removeAll() }
}
