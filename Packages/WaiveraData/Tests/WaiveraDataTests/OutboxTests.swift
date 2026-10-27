import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Outbox")
struct OutboxTests {
    private let sendRoute = "POST api/chat/send"

    private func opened() async -> ChatHarness {
        let harness = ChatHarness()
        await harness.transport.set("GET api/chat/7/messages/pagination", jsonArray([message(1)]))
        await harness.begin()
        await harness.engine.open(conversationId: 7)
        return harness
    }

    private func timeline(_ harness: ChatHarness) -> MessageTimeline? {
        harness.engine.timelineCells.cell(7).current.value
    }

    @Test func blankTextSendsNothing() async {
        let harness = await opened()
        #expect(await harness.engine.send(text: "   \n", attachment: nil, conversationId: 7) == nil)
        #expect(timeline(harness)?.pending.isEmpty == true)
    }

    @Test func hubSendCarriesTheClientIdAndConfirms() async throws {
        let harness = await opened()
        harness.realtime.connect()
        let entry = try #require(await harness.engine.send(text: " hi there ", attachment: nil, conversationId: 7))
        #expect(await eventually { timeline(harness)?.pending.isEmpty == true })
        #expect(harness.realtime.log.sent.first?.clientMessageId == entry.clientMessageId)
        #expect(harness.realtime.log.sent.first?.text == "hi there")
        let confirmed = timeline(harness)?.messages.last
        #expect(confirmed?.id == 10_001)
        #expect(confirmed?.isMine == true)
        #expect(await harness.transport.count(sendRoute) == 0)
    }

    @Test func restFallbackWhenTheHubIsDown() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .fixture("rest-chat-send-message"))
        let entry = try #require(await harness.engine.send(text: "via rest", attachment: nil, conversationId: 7))
        #expect(await eventually { timeline(harness)?.pending.isEmpty == true })
        let body = try #require(await harness.transport.bodies(sendRoute).first)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["clientMessageId"] as? String == entry.clientMessageId)
    }

    @Test func transientFailuresRetryThenShowRetry() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(503))
        let entry = try #require(await harness.engine.send(text: "flaky", attachment: nil, conversationId: 7))
        #expect(await eventually { await harness.transport.count(sendRoute) == 1 })
        #expect(await eventually { timeline(harness)?.pending.first?.state == .queued(attempt: 1) })
        await harness.clock.advance(by: 1)
        #expect(await eventually { await harness.transport.count(sendRoute) == 2 })
        await harness.clock.advance(by: 2)
        #expect(await eventually { await harness.transport.count(sendRoute) == 3 })
        #expect(await eventually { timeline(harness)?.pending.first?.isFailed == true })
        #expect(timeline(harness)?.pending.first?.clientMessageId == entry.clientMessageId)
        await harness.clock.advance(by: 60)
        #expect(await harness.transport.count(sendRoute) == 3)
    }

    @Test func permanentFailureShowsRetryAtOnce() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(403))
        _ = await harness.engine.send(text: "nope", attachment: nil, conversationId: 7)
        #expect(await eventually { timeline(harness)?.pending.first?.state == .failed(.forbidden) })
        #expect(await harness.transport.count(sendRoute) == 1)
    }

    @Test func manualRetryReusesTheClientId() async throws {
        let harness = await opened()
        await harness.transport.enqueue(sendRoute, .status(400), .fixture("rest-chat-send-message"))
        let entry = try #require(await harness.engine.send(text: "again", attachment: nil, conversationId: 7))
        #expect(await eventually { timeline(harness)?.pending.first?.isFailed == true })
        await harness.engine.retry(clientMessageId: entry.clientMessageId)
        #expect(await eventually { timeline(harness)?.pending.isEmpty == true })
        let ids = try await harness.transport.bodies(sendRoute).map { body in
            try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])["clientMessageId"] as? String
        }
        #expect(ids == [entry.clientMessageId, entry.clientMessageId])
    }

    @Test func discardDropsAFailedSend() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(400))
        let entry = try #require(await harness.engine.send(text: "draft", attachment: nil, conversationId: 7))
        #expect(await eventually { timeline(harness)?.pending.first?.isFailed == true })
        await harness.engine.discard(clientMessageId: entry.clientMessageId)
        #expect(timeline(harness)?.pending.isEmpty == true)
        await harness.engine.flushPersistence()
        #expect(await harness.store.load([OutgoingMessage].self, for: .outbox)?.isEmpty == true)
    }

    @Test func echoReconcilesByClientIdBeforeTheAckArrives() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(400))
        let entry = try #require(await harness.engine.send(text: "echo", attachment: nil, conversationId: 7))
        await harness.engine.handle(
            .message(
                message(500, author: viewerId, text: "different", at: 1_792_500_000, clientId: entry.clientMessageId)
            )
        )
        #expect(timeline(harness)?.pending.isEmpty == true)
        #expect(timeline(harness)?.messages.contains { $0.id == 500 } == true)
    }

    @Test func echoWithoutClientIdReconcilesByTextWithinTheWindow() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(400))
        _ = await harness.engine.send(text: "same words", attachment: nil, conversationId: 7)
        _ = await harness.engine.send(text: "other words", attachment: nil, conversationId: 7)
        await harness.engine.handle(.message(message(501, author: viewerId, text: "same words", at: 1_792_500_010)))
        #expect(timeline(harness)?.pending.map(\.text) == ["other words"])
        // Outside the 60 s window it is a different message.
        await harness.engine.handle(.message(message(502, author: viewerId, text: "other words", at: 1_792_500_100)))
        #expect(timeline(harness)?.pending.map(\.text) == ["other words"])
    }

    @Test func outboxSurvivesRelaunchAndResumes() async throws {
        let harness = await opened()
        await harness.transport.setOffline(true)
        _ = await harness.engine.send(text: "offline", attachment: nil, conversationId: 7)
        #expect(await eventually { timeline(harness)?.pending.first?.state == .queued(attempt: 1) })
        await harness.engine.flushPersistence()

        let relaunched = ChatHarness()
        await relaunched.transport.set(sendRoute, .fixture("rest-chat-send-message"))
        let pending = await harness.store.load([OutgoingMessage].self, for: .outbox) ?? []
        await relaunched.store.save(pending, for: .outbox)
        await relaunched.begin()
        #expect(await eventually { await relaunched.transport.count(sendRoute) == 1 })
    }

    @Test func threadRepliesArePendingInTheThreadOnly() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(400))
        _ = await harness.engine.reply(text: "in thread", attachment: nil, rootMessageId: 1, conversationId: 7)
        #expect(await eventually { harness.engine.threadCells.cell(1).current.value?.pending.first?.isFailed == true })
        #expect(timeline(harness)?.pending.isEmpty == true)
        #expect(await harness.engine.pendingMessages(conversationId: 7).count == 1)
    }

    @Test func confirmedSendUpdatesTheInboxPreview() async throws {
        let harness = await opened()
        await harness.transport.set("GET api/chat/all", .fixture("rest-chat-get-all"))
        await harness.engine.refresh()
        harness.realtime.connect()
        _ = await harness.engine.send(text: "latest", attachment: nil, conversationId: 7)
        #expect(
            await eventually {
                harness.engine.conversationsCell.current.value?.first { $0.id == 7 }?.preview == .text("latest")
            }
        )
        #expect(harness.engine.conversationsCell.current.value?.first { $0.id == 7 }?.unreadCount == 1)
    }
}

@Suite("Threads")
struct ThreadTests {
    private func harness() async -> ChatHarness {
        let harness = ChatHarness()
        await harness.transport.set(
            "GET api/chat/7/messages/pagination",
            .fixture("rest-chat-get-messages-pagination-reply")
        )
        await harness.transport.set("GET api/chat/thread/9330", .fixture("rest-chat-get-thread"))
        await harness.begin()
        return harness
    }

    @Test func openJoinsTheConversationGroup() async {
        let harness = await harness()
        await harness.engine.open(rootMessageId: 9330, conversationId: 7)
        #expect(harness.realtime.log.joins == [7])
        // Only the thread is on screen, not the conversation's timeline (IF-02).
        #expect(harness.presence.isThreadActive(9330))
        #expect(!harness.presence.isActive(7))
        let thread = harness.engine.threadCells.cell(9330).current
        #expect(thread.phase == .loaded)
        #expect(thread.value?.root?.id == 9330)
        await harness.engine.close(rootMessageId: 9330, conversationId: 7)
        #expect(harness.realtime.log.leaves == [7])
    }

    @Test func liveReplyCountsOnceAndRepeatsDoNotInflate() async {
        let harness = await harness()
        await harness.engine.open(conversationId: 7)
        let before = harness.engine.timelineCells.cell(7).current.value?.messages.first?.threadReplyCount ?? 0
        let reply = message(9399, text: "late reply", at: 1_792_600_000, parent: 9330)
        await harness.engine.handle(.message(reply))
        await harness.engine.handle(.message(reply))
        let root = harness.engine.timelineCells.cell(7).current.value?.messages.first
        #expect(root?.threadReplyCount == max(before + 1, 3))
        #expect(harness.engine.timelineCells.cell(7).current.value?.messages.count == 1)
        #expect(harness.engine.threadCells.cell(9330).current.value?.replies.last?.id == 9399)
    }

    @Test func reactionsOnRepliesApplyInTheThread() async {
        let harness = await harness()
        await harness.engine.open(rootMessageId: 9330, conversationId: 7)
        harness.realtime.connect()
        let replyId = harness.engine.threadCells.cell(9330).current.value?.replies.first?.id ?? 0
        try? await harness.engine.toggleReaction("👍", messageId: replyId, conversationId: 7)
        let reply = harness.engine.threadCells.cell(9330).current.value?.replies.first
        #expect(reply?.reactions.map(\.emoji) == ["👍"])
    }

    @Test func threadErrorState() async {
        let harness = await harness()
        await harness.transport.set("GET api/chat/thread/9330", .status(404))
        await harness.engine.open(rootMessageId: 9330, conversationId: 7)
        #expect(harness.engine.threadCells.cell(9330).current.error == .notFound)
    }

    @Test func reconnectRefetchesOpenThreads() async {
        let harness = await harness()
        await harness.engine.open(rootMessageId: 9330, conversationId: 7)
        await harness.engine.resync()
        #expect(await harness.transport.count("GET api/chat/thread/9330") == 2)
    }
}

@Suite("Typing")
struct TypingTests {
    @Test func incomingTypingExpiresAfterFiveSeconds() async {
        let clock = TestClock()
        let tracker = TypingTracker(clock: clock)
        await tracker.received(conversationId: 7, userId: "usr_priya_raman", isTyping: true)
        await settle()
        #expect(tracker.cell.current[7] == ["usr_priya_raman"])
        await clock.advance(by: 4)
        #expect(tracker.cell.current[7] == ["usr_priya_raman"])
        await clock.advance(by: 1.1)
        #expect(await eventually { tracker.cell.current[7] == nil })
    }

    @Test func messageFromTheTyperClearsIt() async {
        let tracker = TypingTracker(clock: TestClock())
        await tracker.received(conversationId: 7, userId: "usr_priya_raman", isTyping: true)
        await tracker.messageArrived(conversationId: 7, authorId: "usr_priya_raman")
        #expect(tracker.cell.current.isEmpty)
    }

    @Test func viewerTypingIsIgnored() async {
        let harness = ChatHarness()
        await harness.begin()
        await harness.engine.handle(.typing(TypingEvent(conversationId: 7, userId: viewerId, isTyping: true)))
        #expect(harness.engine.typingTracker.cell.current.isEmpty)
    }

    @Test func outgoingTypingIsThrottledToOnePerThreeSeconds() async {
        let clock = TestClock()
        let sent = LockedValue<[Bool]>([])
        let throttle = TypingThrottle(clock: clock) { _, isTyping in sent.update { $0.append(isTyping) } }
        await throttle.textChanged(conversationId: 7, text: "h")
        await settle()
        await clock.advance(by: 1)
        await throttle.textChanged(conversationId: 7, text: "he")
        await settle()
        await clock.advance(by: 1)
        await throttle.textChanged(conversationId: 7, text: "hel")
        await settle()
        #expect(sent.get() == [true])
        await clock.advance(by: 1.5)
        await throttle.textChanged(conversationId: 7, text: "hell")
        await settle()
        #expect(sent.get() == [true, true])
        await clock.advance(by: 1.9)
        #expect(await eventually { sent.get() == [true, true, false] })
    }

    @Test func sendStopsTyping() async {
        let harness = ChatHarness()
        await harness.begin()
        harness.realtime.connect()
        await harness.engine.composerChanged(conversationId: 7, text: "typing")
        _ = await harness.engine.send(text: "typing", attachment: nil, conversationId: 7)
        #expect(harness.realtime.log.typing.map(\.1) == [true, false])
    }
}
