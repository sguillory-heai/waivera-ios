import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraDesign

@testable import ChatFeature

/// The approved Android behaviour ported in phase B: the send line, the focus overlay's flow,
/// the group header and the long-content rules.
@Suite("Conversation port")
@MainActor
struct ConversationPortTests {
    // MARK: Send line (Android FooterPhase)

    @Test func sendingStaysQuietForTheFirstBeat() {
        #expect(PendingFooterPhase(.sending, sendingLabelDue: false) == .quiet)
        #expect(PendingFooterPhase(.sending, sendingLabelDue: true) == .sending)
        #expect(PendingFooterPhase.sendingLabelDelay == MotionTiming.sendingLabelDelay)
    }

    @Test func aFailureAndAQueuedSendShowAtOnce() {
        #expect(PendingFooterPhase(.failed(.offline), sendingLabelDue: false) == .failed)
        #expect(PendingFooterPhase(.queued(attempt: 1), sendingLabelDue: false) == .queued)
    }

    @Test func theSendLineCopyMatchesAndroid() {
        #expect(PendingFooterPhase.quiet.copyKey == nil)
        #expect(ConversationStrings.text("failed") == "Not sent")
        #expect(ConversationStrings.text("sending") == "Sending…")
        #expect(ConversationStrings.text("queued") == "Sends when you’re back online")
        #expect(ConversationStrings.format("sent.at", "9:41 AM") == "Sent · 9:41 AM")
    }

    // MARK: Focus overlay flow (spec §9.1)

    @Test func deleteFromTheOverlayClosesItThenAsksAfterTheCloseWait() async throws {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let mine = try #require(model.messageRows.first { $0.isMine }?.message)
        model.openActions(mine)
        #expect(model.interactions.focus?.message.id == mine.id)
        #expect(model.interactions.sheet == nil, "the overlay is not a sheet")
        let request = Task { await model.interactions.requestDelete(messageId: mine.id) }
        #expect(await eventually { model.interactions.focus == nil })
        #expect(model.interactions.sheet == nil, "the confirmation waits for the overlay to go")
        // Other sleepers share the manual clock, so keep advancing until the confirmation shows.
        var confirmed = false
        for _ in 0..<20 where !confirmed {
            harness.clock.advance(by: MotionTiming.focusCloseWait / 4)
            confirmed = await eventually(timeout: 0.1) {
                model.interactions.sheet == .confirmDelete(messageId: mine.id)
            }
        }
        #expect(confirmed)
        request.cancel()
        #expect(harness.recorder.haptics.isEmpty, "the overlay never vibrates")
        task.cancel()
    }

    @Test func reactingFromTheOverlayClosesItSilently() async throws {
        let harness = await ModelHarness()
        let model = harness.conversation()
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let message = try #require(model.messageRows.last?.message)
        model.openActions(message)
        await model.interactions.react(messageId: message.id, emoji: "👍")
        #expect(model.interactions.focus == nil)
        #expect(harness.recorder.haptics.isEmpty)
        task.cancel()
    }

    @Test func editAndReplyCloseTheOverlay() async throws {
        let harness = await ModelHarness()
        var opened: [Int] = []
        let model = harness.conversation { root, _ in opened.append(root) }
        let task = Task { await model.run() }
        #expect(await eventually { model.isReady })
        let mine = try #require(model.messageRows.first { $0.isMine && !$0.message.copyableText.isEmpty }?.message)
        model.openActions(mine)
        model.startEdit(mine)
        #expect(model.interactions.focus == nil)
        #expect(model.state.editingMessageID == mine.id)
        model.cancelEdit()
        model.openActions(mine)
        model.openThread(mine)
        #expect(model.interactions.focus == nil)
        #expect(opened.count == 1)
        task.cancel()
    }

    // MARK: Group header (spec §9.2)

    @Test func onlyAGroupCountsItsMembers() {
        let viewer = ChatUser(id: "usr_me", firstName: "Alex")
        let priya = ChatUser(id: "usr_priya", firstName: "Priya")
        let jordan = ChatUser(id: "usr_jordan", firstName: "Jordan")
        let group = Conversation(id: 1, kind: .group, viewerId: "usr_me", participants: [viewer, priya, jordan, priya])
        #expect(ConversationModel.memberCount(group) == 3)
        let direct = Conversation(id: 2, kind: .direct, viewerId: "usr_me", participants: [viewer, priya])
        #expect(ConversationModel.memberCount(direct) == nil)
        var channel = Conversation(id: 3, kind: .channel, viewerId: "usr_me", participants: [viewer, priya, jordan])
        channel.channel = nil
        #expect(ConversationModel.memberCount(channel) == nil)
    }

    @Test func theGroupTitleCutsOnlyTheName() {
        let title = ConversationStrings.title(.group(firstName: "Maria-Fernanda R.", otherCount: 4))
        let name = ConversationStrings.groupFirstName("Maria-Fernanda R.")
        #expect(title == "Maria-Fernanda R. & 4 others")
        #expect(GroupTitle.nameRange(in: title, name: name) != nil)
        #expect(ConversationStrings.threadIn("north-region") == "In north-region")
    }

    // MARK: Long content (wave 28)

    @Test func mentionsNeverSplitAtTheirHyphens() {
        let attributed = RichTextAttributes.attributed([.text("Hi ", marks: [], href: nil), .mention("Maria-Fernanda")])
        let shown = String(attributed.characters)
        #expect(shown == "Hi @Maria\u{2011}Fernanda")
        #expect(!shown.contains("-"))
    }

    @Test func ticketMetaLabelsKeepTheirWidthAndLongValuesStack() {
        let pair: CGFloat = 400
        let gap: CGFloat = 16
        #expect(TicketMetaFit.valueMaxWidth(pairWidth: pair, gap: gap, labelWidth: 100, valueWidth: 60) == 284)
        #expect(TicketMetaFit.valueMaxWidth(pairWidth: pair, gap: gap, labelWidth: 100, valueWidth: 900) == 284)
        #expect(TicketMetaFit.valueMaxWidth(pairWidth: pair, gap: gap, labelWidth: 250, valueWidth: 40) == 134)
        #expect(TicketMetaFit.valueMaxWidth(pairWidth: pair, gap: gap, labelWidth: 250, valueWidth: 900) == nil)
        #expect(TicketMetaFit.valueMaxWidth(pairWidth: pair, gap: gap, labelWidth: 401, valueWidth: 0) == nil)
    }
}
