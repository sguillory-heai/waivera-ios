import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraDesign
import WaiveraTestSupport

@testable import ChatFeature

@MainActor
@Suite("Conversation model")
struct ConversationModelTests {
    // MARK: States

    @Test func anInvalidIdIsRejectedLocally() async {
        let harness = await ModelHarness()
        let model = harness.conversation(0)
        #expect(model.state.content == .invalid)
        await model.run()
        #expect(harness.fakes.chat.calls.count("open:") == 0)
    }

    @Test func loadingThenMessagesThenMarkedRead() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        #expect(model.state.content == .loading)
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        #expect(!model.state.items.isEmpty)
        #expect(await eventually { harness.fakes.chat.calls.count("markRead:7") >= 1 })
        #expect(await eventually { model.state.title != nil && model.state.canWrite == true })
        task.cancel()
        #expect(await eventually { harness.fakes.chat.calls.count("close:7") == 1 })
    }

    @Test func anEmptyConversationShowsTheEmptyState() async {
        let harness = await ModelHarness(.empty)
        let model = harness.conversation(7)
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .empty })
        task.cancel()
    }

    @Test func aLoadFailureShowsTheErrorAndRetryRecovers() async {
        let harness = await ModelHarness(.failing)
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.content == .error(.server(statusCode: 503)) })
        harness.fakes.setControls(FakeControls())
        await model.retryLoad()
        #expect(await eventually { model.isReady })
        task.cancel()
    }

    @Test func reconnectingShowsInTheHeaderAndClearsOnReconnect() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        harness.fakes.realtime.drop(attempt: 2)
        #expect(await eventually { model.state.subtitle == .reconnecting })
        harness.fakes.realtime.connect()
        #expect(await eventually { model.state.subtitle == nil })
        task.cancel()
    }

    @Test func reactionsNeedALiveConnection() async throws {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let message = try #require(model.messageRows.first?.message)
        harness.fakes.realtime.drop()
        #expect(await eventually { model.state.subtitle == .reconnecting })
        await model.interactions.react(messageId: message.id, emoji: "👍")
        #expect(model.interactions.toast?.kind == .failed(.reactionNeedsConnection, detail: nil))
        #expect(harness.fakes.chat.calls.count("react:") == 0)
        harness.fakes.realtime.connect()
        #expect(await eventually { model.state.subtitle == nil })
        await model.interactions.react(messageId: message.id, emoji: "👍")
        #expect(harness.fakes.chat.calls.count("react:\(message.id):👍") == 1)
        task.cancel()
    }

    // MARK: Sending (03 §11)

    @Test func someoneElsesMessageArrivingOnScreenPlaysTheReceiveCue() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        #expect(!harness.recorder.haptics.contains(.messageReceivedWhileVisible), "history never buzzes")
        var incoming = ChatMessage(
            id: 20_500,
            conversationId: 7,
            isMine: false,
            createdAt: harness.clock.now.addingTimeInterval(3_600)
        )
        incoming.authorId = "usr_priya_raman"
        incoming.plaintext = "Running late"
        await harness.fakes.chat.receive(incoming)
        #expect(await eventually { harness.recorder.haptics.contains(.messageReceivedWhileVisible) })
        task.cancel()
    }

    @Test func aSendIsOptimisticAndKeepsItsRowWhenConfirmed() async throws {
        let harness = await ModelHarness()
        await harness.fakes.chat.setSendOutcome(.hold)
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        model.draft = "  On my way  "
        await model.send()
        #expect(model.draft.isEmpty)
        #expect(await eventually { model.pendingRows.contains { $0.outgoing.text == "On my way" } })
        let row = try #require(model.pendingRows.first { $0.outgoing.text == "On my way" })
        #expect(row.outgoing.state == .sending)
        #expect(harness.recorder.haptics.contains(.messageSent))
        await harness.fakes.chat.confirmPending()
        #expect(await eventually { model.messageRows.contains { $0.key == row.key } })
        task.cancel()
    }

    @Test func aFailureWhileOpenRaisesTheBannerOnce() async {
        let harness = await ModelHarness()
        await harness.fakes.chat.setSendOutcome(.fail(.offline))
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        // The demo's failed row was already there: inline Retry, no banner.
        #expect(model.state.sendError == nil)
        model.draft = "Hello"
        await model.send()
        #expect(await eventually { model.state.sendError == .offline })
        #expect(harness.recorder.haptics.contains(.failure))
        model.draft = "Hello again"
        model.draftChanged()
        #expect(model.state.sendError == nil)
        task.cancel()
    }

    @Test func aRetriedSendThatLandsPlaysSuccess() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.pendingRows.contains { $0.outgoing.clientMessageId == "demo-failed-send" } })
        await model.retry(clientMessageId: "demo-failed-send")
        #expect(await eventually { harness.recorder.haptics.contains(.success) })
        #expect(!model.pendingRows.contains { $0.outgoing.clientMessageId == "demo-failed-send" })
        task.cancel()
    }

    @Test func editingAFailedRowPutsItsTextBack() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { !model.pendingRows.isEmpty })
        let failed = model.pendingRows[0].outgoing
        await model.editFailed(failed)
        #expect(model.draft == failed.text)
        #expect(await eventually { model.pendingRows.isEmpty })
        task.cancel()
    }

    @Test func anImageUploadFailureRestoresTheDraftAndImage() async {
        let harness = await ModelHarness()
        harness.fakes.attachments.uploadFailure.update { $0 = .attachmentUploadFailed }
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.canWrite == true })
        let image = StagedImage(data: Data([1, 2, 3]), fileName: "photo.jpg", mimeType: "image/jpeg")
        model.stageImage(image)
        model.draft = "Look"
        await model.send()
        #expect(model.draft == "Look")
        #expect(model.state.stagedImage == image)
        #expect(model.state.sendError == .server)
        #expect(!model.state.isUploading)
        task.cancel()
    }

    @Test func anImageUploadsBeforeItSends() async {
        let harness = await ModelHarness()
        await harness.fakes.chat.setSendOutcome(.hold)
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.canWrite == true })
        model.stageImage(StagedImage(data: Data([1]), fileName: "photo.jpg", mimeType: "image/jpeg"))
        #expect(model.canSend)
        await model.send()
        #expect(harness.fakes.attachments.calls.count("upload:photo.jpg") == 1)
        #expect(model.state.stagedImage == nil)
        #expect(await eventually { model.pendingRows.contains { $0.outgoing.attachment != nil } })
        task.cancel()
    }

    @Test func editSavesThroughTheActions() async throws {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let mine = try #require(model.messageRows.first { $0.isMine && !$0.message.copyableText.isEmpty }?.message)
        model.startEdit(mine)
        #expect(model.state.editingMessageID == mine.id)
        #expect(model.draft == mine.copyableText)
        model.draft = "Updated"
        await model.send()
        #expect(harness.fakes.chat.calls.count("edit:\(mine.id)") == 1)
        #expect(model.state.editingMessageID == nil)
        #expect(model.draft.isEmpty)
        task.cancel()
    }

    // MARK: Typing and read-only

    @Test func typingShowsOtherPeopleOnly() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        harness.fakes.chat.setTyping(["usr_priya_raman"], in: 7)
        #expect(await eventually { if case .one = model.state.typing { true } else { false } })
        harness.fakes.chat.setTyping([], in: 7)
        #expect(await eventually { model.state.typing == nil })
        task.cancel()
    }

    @Test func composerChangesSendTheTypingSignal() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.canWrite == true })
        model.draft = "H"
        model.draftChanged()
        #expect(await eventually { harness.fakes.chat.calls.count("typing:7") >= 1 })
        task.cancel()
    }

    // MARK: Deep link (03 §9)

    @Test func aDeepLinkedMessageIsScrolledToAndHighlighted() async {
        let harness = await ModelHarness()
        let model = harness.conversation(target: 9312)
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let key = model.keyFor(9312)
        #expect(key != nil)
        await harness.advance(by: ConversationModel.highlightScrollDelay + 0.05)
        #expect(await eventually { model.state.highlightKey == key })
        #expect(model.state.scrollCommand?.target == key.map(ScrollCommand.Target.key))
        await harness.advance(by: ConversationModel.highlightDuration + 0.1)
        #expect(await eventually { model.state.highlightKey == nil })
        task.cancel()
    }

    @Test func aMissingTargetPagesOlderThenGivesUpQuietly() async {
        let harness = await ModelHarness()
        let model = harness.conversation(target: 1)
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.state.highlightKey == nil)
        #expect(harness.fakes.chat.calls.count("loadOlder:7") <= ConversationModel.maxHighlightPages)
        #expect(harness.fakes.chat.calls.count("loadAround:7:1") == 1, "the context window is tried first")
        task.cancel()
    }

    @Test func aFailedOlderPageOffersRetryWithoutMarkingTheRowsStale() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        await harness.fakes.chat.setOlderPageFailure(.offline)
        #expect(await eventually { model.state.hasOlder })
        await model.loadOlder()
        #expect(await eventually { model.state.olderFailed })
        #expect(model.state.isStale == false)
        #expect(model.state.content == .messages)
        await harness.fakes.chat.setOlderPageFailure(nil)
        await model.loadOlder()
        #expect(await eventually { !model.state.olderFailed })
        task.cancel()
    }

}

extension ConversationModelTests {
    // MARK: Actions (03 §14)

    @Test func deleteAsksFirstThenDeletes() async throws {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let mine = try #require(model.messageRows.first { $0.isMine }?.message)
        model.interactions.requestDelete(messageId: mine.id)
        #expect(model.interactions.sheet == .confirmDelete(messageId: mine.id))
        #expect(harness.fakes.chat.calls.count("delete:") == 0)
        await model.interactions.confirmDelete(messageId: mine.id)
        #expect(harness.fakes.chat.calls.count("delete:\(mine.id)") == 1)
        #expect(model.interactions.sheet == nil)
        task.cancel()
    }

    @Test func bookmarkTogglesWithUndo() async throws {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let message = try #require(model.messageRows.last?.message)
        await model.interactions.toggleBookmark(messageId: message.id)
        let toast = try #require(model.interactions.toast)
        #expect(
            [ChatToast.Kind.bookmarkSaved(messageId: message.id), .bookmarkRemoved(messageId: message.id)].contains(
                toast.kind
            )
        )
        await model.interactions.undoBookmark(messageId: message.id)
        #expect(harness.fakes.bookmarks.calls.count("toggle:\(message.id)") == 2)
        task.cancel()
    }

    @Test func copyKeepsTheSheetOpenAndMarksItCopied() async throws {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let message = try #require(model.messageRows.first { !$0.message.copyableText.isEmpty }?.message)
        model.openActions(message)
        model.interactions.copy(message)
        #expect(harness.recorder.copied == [message.copyableText])
        guard case .actions(let sheet) = model.interactions.sheet else {
            Issue.record("Sheet closed")
            return
        }
        #expect(sheet.copied)
        task.cancel()
    }

    @Test func replyOpensTheThreadOnItsRoot() async throws {
        let harness = await ModelHarness()
        var opened: [Int] = []
        let model = harness.conversation(onOpenThread: { root, _ in opened.append(root) })
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let message = try #require(model.messageRows.first?.message)
        model.openThread(message)
        #expect(opened == [message.id])
        task.cancel()
    }

    @Test func blockedAttachmentsAreNotRetried() async {
        let harness = await ModelHarness()
        harness.fakes.attachments.blockedMessageIds.update { $0 = [42] }
        let model = harness.conversation()
        await #expect(throws: WaiveraError.attachmentBlocked) { try await model.interactions.download(messageId: 42) }
        #expect(harness.fakes.attachments.calls.count("download:42") == 1)
    }

    @Test func unsafeLinksNeverOpen() async throws {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let safe = try #require(URL(string: "https://waivera.example/a"))
        model.interactions.openLink(try #require(URL(string: "javascript:alert(1)")))
        model.interactions.openLink(safe)
        #expect(harness.recorder.openedInApp == [safe])
    }

    // MARK: Call handoff (03 §19)

    @Test func theCallOpensTheWebLobby() async {
        let harness = await ModelHarness(webBaseURL: URL(string: "https://app.example.test"))
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.call.isAvailable })
        await model.openCall()
        #expect(harness.recorder.openedExternally.count == 1)
        #expect(!model.state.call.isOpening)
        task.cancel()
    }

    @Test func aCallThatCannotOpenShowsAToast() async {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.state.call.isAvailable })
        await model.openCall()
        #expect(model.interactions.toast?.kind == .failed(.call, detail: .configurationMissing))
        #expect(harness.recorder.openedExternally.isEmpty)
        task.cancel()
    }
}
