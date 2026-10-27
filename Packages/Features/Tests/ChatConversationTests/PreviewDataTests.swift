import Foundation
import Testing
import WaiveraData
import WaiveraTestSupport

@testable import ChatFeature

/// The preview and snapshot states must keep showing what their names promise as the demo
/// data changes.
@Suite("Preview data")
struct PreviewDataTests {
    private func rows(_ state: ConversationState) -> [MessageRow] {
        state.items.compactMap { item in
            if case .message(let row) = item { return row }
            return nil
        }
    }

    @Test func theMessagesStateShowsEveryKindOfRow() {
        let state = ChatPreviewData.conversation(.messages)
        let rows = rows(state)
        #expect(state.content == .messages)
        #expect(state.canWrite == true)
        #expect(rows.contains { $0.isMine } && rows.contains { !$0.isMine })
        #expect(rows.contains { !$0.reactions.isEmpty })
        #expect(rows.contains { $0.message.attachment != nil })
        #expect(rows.contains { $0.message.threadReplyCount > 0 })
        #expect(rows.contains { $0.rich != nil })
        #expect(rows.contains { $0.message.id == ChatPreviewData.editedMessageId && $0.isMine })
        #expect(state.items.contains { if case .callLog = $0 { true } else { false } })
        let pending = state.items.compactMap { item -> OutgoingMessage.State? in
            if case .pending(let row) = item { return row.outgoing.state }
            return nil
        }
        #expect(pending.contains(.sending))
        #expect(pending.contains { if case .failed = $0 { true } else { false } })
    }

    @Test func theBotStateIsReadOnlyWithATicketCard() {
        let state = ChatPreviewData.conversation(.readOnlyBot)
        #expect(state.canWrite == false)
        #expect(state.readOnlyReason == .automated)
        #expect(state.isBotConversation)
        #expect(rows(state).contains { $0.ticket != nil })
    }

    @Test func eachConversationVariantSetsItsState() {
        #expect(ChatPreviewData.conversation(.loading).content == .loading)
        #expect(ChatPreviewData.conversation(.empty).content == .empty)
        #expect(ChatPreviewData.conversation(.error).content == .error(.offline))
        let reconnecting = ChatPreviewData.conversation(.reconnecting)
        #expect(reconnecting.subtitle == .reconnecting && reconnecting.isStale)
        #expect(ChatPreviewData.conversation(.typing).typing != nil)
        #expect(ChatPreviewData.conversation(.sendError).sendError == .offline)
        #expect(ChatPreviewData.conversation(.editing).editingMessageID == ChatPreviewData.editedMessageId)
        #expect(!ChatPreviewData.draft(.editing).isEmpty)
        #expect(ChatPreviewData.conversation(.liveCall).call.isLive)
    }

    @Test func eachThreadVariantSetsItsState() {
        let replies = ChatPreviewData.thread(.replies)
        #expect(replies.content == .ready)
        #expect(replies.root?.message.id == ChatPreviewData.threadRootId)
        #expect(replies.replyCount > 0 && !replies.replies.isEmpty)
        #expect(ChatPreviewData.thread(.loading).content == .loading)
        #expect(ChatPreviewData.thread(.empty).replies.isEmpty)
        #expect(ChatPreviewData.thread(.error).content == .error(.offline))
        let readOnly = ChatPreviewData.thread(.readOnly)
        #expect(readOnly.canWrite == false && readOnly.readOnlyReason == .readOnlyThread)
    }

    @MainActor
    @Test func previewModelsUseTheFixedDemoClock() {
        let conversation = ChatPreviewData.conversationModel(.editing)
        let thread = ChatPreviewData.threadModel(.replies)
        #expect(conversation.clock.now == DemoData.now && thread.clock.now == DemoData.now)
        #expect(conversation.clock.timeZone == DemoData.timeZone)
        #expect(conversation.draft == ChatPreviewData.draft(.editing))
        #expect(conversation.state == ChatPreviewData.conversation(.editing))
    }
}
