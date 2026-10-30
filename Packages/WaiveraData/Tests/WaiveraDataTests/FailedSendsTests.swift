import Foundation
import Testing
import WaiveraAPI
import WaiveraRealtime

@testable import WaiveraData

/// The failed-sends stream behind "Not sent" on the inbox and Today (Android `observeFailedSends`):
/// a conversation is in it while a send of mine there needs Retry, and leaves once it goes out
/// or is discarded. Sends still on their way do not count.
@Suite("Failed sends")
struct FailedSendsTests {
    private let sendRoute = "POST api/chat/send"

    private func opened() async -> ChatHarness {
        let harness = ChatHarness()
        await harness.transport.set("GET api/chat/7/messages/pagination", jsonArray([message(1)]))
        await harness.begin()
        await harness.engine.open(conversationId: 7)
        return harness
    }

    private func failed(_ harness: ChatHarness) -> Set<Int> {
        harness.engine.failedSendsCell.current
    }

    private func first(_ stream: AsyncStream<Set<Int>>) async -> Set<Int>? {
        var iterator = stream.makeAsyncIterator()
        return await iterator.next()
    }

    @Test func aFailedSendMarksItsConversationUntilRetryDelivers() async throws {
        let harness = await opened()
        await harness.transport.enqueue(sendRoute, .status(400), .fixture("rest-chat-send-message"))
        let entry = try #require(await harness.engine.send(text: "again", attachment: nil, conversationId: 7))
        #expect(await eventually { failed(harness) == [7] })
        #expect(await first(harness.engine.failedSends()) == [7])
        await harness.engine.retry(clientMessageId: entry.clientMessageId)
        #expect(await eventually { failed(harness).isEmpty })
    }

    @Test func aQueuedSendIsNotFailed() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(503))
        _ = try #require(await harness.engine.send(text: "flaky", attachment: nil, conversationId: 7))
        #expect(await eventually { await harness.transport.count(sendRoute) == 1 })
        let timeline = harness.engine.timelineCells.cell(7)
        #expect(await eventually { timeline.current.value?.pending.first?.state == .queued(attempt: 1) })
        #expect(failed(harness).isEmpty)
    }

    @Test func discardingTheSendClearsIt() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(400))
        let entry = try #require(await harness.engine.send(text: "draft", attachment: nil, conversationId: 7))
        #expect(await eventually { failed(harness) == [7] })
        await harness.engine.discard(clientMessageId: entry.clientMessageId)
        #expect(failed(harness).isEmpty)
    }

    @Test func aFailedThreadReplyMarksItsConversation() async throws {
        let harness = await opened()
        await harness.transport.set(sendRoute, .status(400))
        _ = await harness.engine.reply(text: "in thread", attachment: nil, rootMessageId: 1, conversationId: 7)
        #expect(await eventually { failed(harness) == [7] })
    }

    @Test func aFailedSendSavedBeforeRelaunchShowsAtSignInAndSignOutClearsIt() async {
        let harness = ChatHarness()
        let saved = OutgoingMessage(
            clientMessageId: "client-1",
            conversationId: 12,
            parentMessageId: nil,
            text: "kept",
            doc: nil,
            createdAt: Date(timeIntervalSince1970: 1_792_500_000),
            state: .failed(.forbidden),
            attempts: 1,
            authorId: viewerId
        )
        await harness.store.save([saved], for: .outbox)
        #expect(failed(harness).isEmpty)
        await harness.begin()
        #expect(failed(harness) == [12])
        await harness.engine.end()
        #expect(failed(harness).isEmpty)
    }

    @Test func aSourceWithoutAnOutboxReportsNothing() async {
        let stream = NoOutboxConversations().failedSends()
        #expect(await first(stream) == [])
    }
}

/// Uses the protocol's default `failedSends()`.
private struct NoOutboxConversations: ConversationsRepository {
    func conversations() -> AsyncStream<Resource<[Conversation]>> { AsyncStream { $0.finish() } }
    func refresh() async {}
    func conversation(id: Int) async throws -> Conversation { throw WaiveraError.notFound }
    func typing() -> AsyncStream<[Int: [String]]> { AsyncStream { $0.finish() } }
    func totalUnread() -> AsyncStream<Int> { AsyncStream { $0.finish() } }
    func openDirectConversation(with userId: String) async throws -> Conversation { throw WaiveraError.notFound }
    func createConversation(participantIds: [String]) async throws -> Conversation { throw WaiveraError.notFound }
    func leave(conversationId: Int) async throws {}
}
