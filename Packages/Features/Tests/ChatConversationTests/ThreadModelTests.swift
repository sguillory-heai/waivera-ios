import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraDesign
import WaiveraTestSupport

@testable import ChatFeature

@MainActor
@Suite("Thread model")
struct ThreadModelTests {
    private func pendingRows(_ model: ThreadModel) -> [PendingRow] {
        model.state.replies.compactMap { item in
            if case .pending(let row) = item { return row }
            return nil
        }
    }

    @Test func aThreadWithoutAConversationIsInvalid() async {
        let harness = await ModelHarness()
        let model = harness.thread(conversation: nil)
        #expect(model.state.content == .invalid)
        await model.run()
        #expect(harness.fakes.chat.calls.count("openThread:") == 0)
        #expect(harness.thread(0).state.content == .invalid)
    }

    @Test func loadsTheRootAndRepliesAndMarksRead() async {
        let harness = await ModelHarness()
        let model = harness.thread()
        #expect(model.state.content == .loading)
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready })
        #expect(model.state.root?.message.id == 9330)
        #expect(!model.state.replies.isEmpty)
        #expect(model.state.replyCount > 0)
        #expect(await eventually { harness.fakes.chat.calls.count("markThreadRead:9330") >= 1 })
        task.cancel()
        #expect(await eventually { harness.fakes.chat.calls.count("closeThread:9330") == 1 })
    }

    @Test("IF-09: someone else's reply arriving in the open thread plays the receive cue")
    func someoneElsesReplyPlaysTheReceiveCue() async {
        let harness = await ModelHarness()
        let model = harness.thread()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready })
        #expect(!harness.recorder.haptics.contains(.messageReceivedWhileVisible), "history never buzzes")
        var incoming = ChatMessage(
            id: 20_600,
            conversationId: 7,
            isMine: false,
            createdAt: harness.clock.now.addingTimeInterval(3_600)
        )
        incoming.authorId = "usr_priya_raman"
        incoming.plaintext = "On it"
        incoming.parentMessageId = 9330
        incoming.threadRootMessageId = 9330
        await harness.fakes.chat.receive(incoming)
        #expect(await eventually { harness.recorder.haptics.contains(.messageReceivedWhileVisible) })
        task.cancel()
    }

    @Test func aThreadWithNoRepliesIsReadyAndEmpty() async {
        let harness = await ModelHarness()
        let model = harness.thread(424_242)
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready })
        #expect(model.state.replies.isEmpty)
        task.cancel()
    }

    @Test func aLoadFailureShowsTheErrorAndRetryRecovers() async {
        let harness = await ModelHarness(.failing)
        let model = harness.thread()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .error(.server(statusCode: 503)) })
        harness.fakes.setControls(FakeControls())
        await model.retryLoad()
        #expect(await eventually { model.state.content == .ready })
        task.cancel()
    }

    @Test func reconnectingShowsInTheHeader() async {
        let harness = await ModelHarness()
        let model = harness.thread()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready })
        harness.fakes.realtime.drop()
        #expect(await eventually { model.state.subtitle == .reconnecting })
        harness.fakes.realtime.connect()
        #expect(await eventually { model.state.subtitle == nil })
        task.cancel()
    }

    @Test func aReplyIsOptimisticAndTextOnly() async {
        let harness = await ModelHarness()
        await harness.fakes.chat.setSendOutcome(.hold)
        let model = harness.thread()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready && model.state.canWrite == true })
        model.draft = "Thanks"
        model.draftChanged()
        await model.send()
        #expect(model.draft.isEmpty)
        #expect(harness.fakes.chat.calls.count("reply:9330") == 1)
        #expect(await eventually { pendingRows(model).contains { $0.outgoing.text == "Thanks" } })
        // Threads send no typing events (04 §1).
        #expect(harness.fakes.chat.calls.count("typing:") == 0)
        task.cancel()
    }

    @Test func aReplyFailureWhileOpenRaisesTheBanner() async {
        let harness = await ModelHarness()
        await harness.fakes.chat.setSendOutcome(.fail(.channelArchived))
        let model = harness.thread()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready && model.state.canWrite == true })
        model.draft = "Thanks"
        await model.send()
        #expect(await eventually { model.state.sendError == .archived })
        #expect(ConversationStrings.sendError(.archived, noun: .reply).contains("reply"))
        task.cancel()
    }

    @Test func replyOnTheSheetFocusesTheComposer() async throws {
        let harness = await ModelHarness()
        let model = harness.thread()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready && model.state.canWrite == true })
        let root = try #require(model.state.root?.message)
        model.openActions(root)
        guard case .actions(let sheet) = model.interactions.sheet else {
            Issue.record("No action sheet")
            return
        }
        #expect(sheet.canReply)
        let before = model.state.focusRequest
        model.replyFromSheet()
        #expect(model.state.focusRequest == before + 1)
        #expect(model.interactions.sheet == nil)
        task.cancel()
    }

    @Test func aDeepLinkedReplyIsHighlighted() async throws {
        let harness = await ModelHarness()
        let probe = harness.thread()
        let probeTask = Task { await probe.run() }
        #expect(await eventually { probe.state.content == .ready })
        probeTask.cancel()
        let replyId = try #require(
            probe.state.replies.lazy.compactMap { item -> Int? in
                if case .message(let row) = item { return row.message.id }
                return nil
            }.first
        )
        let model = harness.thread(target: replyId)
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready })
        await harness.advance(by: ThreadModel.highlightScrollDelay + 0.05)
        #expect(await eventually { model.state.highlightKey == model.keyFor(replyId) })
        #expect(model.state.highlightKey != nil)
        task.cancel()
    }

    @Test func aTargetOutsideTheThreadIsIgnoredWithoutError() async {
        let harness = await ModelHarness()
        let model = harness.thread(target: 1)
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .ready })
        await harness.advance(by: 1)
        #expect(model.state.highlightKey == nil)
        #expect(model.state.content == .ready)
        task.cancel()
    }
}
