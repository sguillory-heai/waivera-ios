import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ChatFeature

/// v7 items 3 and 4, the one-line typing preview, "Not sent" and the removal beat (Android
/// `ConversationPresentationTest`, `ChatListTypingPreviewLayoutTest`, `ChatListStateHolderTest`).
@MainActor
struct ChatListRowRulesTests {
    let text = EnglishText()

    static let group = Sample.conversation(
        #"{"id": 63, "participants": [\#(Sample.me), \#(Sample.priya), \#(Sample.jordan), \#(Sample.sam)]}"#
    )
    static let direct = Sample.conversation(#"{"id": 7, "participants": [\#(Sample.me), \#(Sample.priya)]}"#)

    private func row(_ conversation: Conversation, typing: [String] = [], failed: Bool = false) -> ChatRow {
        ChatRowBuilder(
            text: text,
            typingUserIds: typing,
            timeLabel: "4m",
            isMarkedRead: false,
            isOpeningCall: false,
            arrivalKey: nil,
            isSendFailed: failed
        ).row(conversation)
    }

    @Test("A group title names the part that may be cut and its short count")
    func groupTitleParts() {
        let group = row(Self.group)
        #expect(group.title == "Priya Raman & 2 others")
        #expect(group.titleName == "Priya Raman")
        #expect(group.titleCompactCount == "+2")
        #expect(group.title.hasPrefix(group.titleName ?? "-"))
    }

    @Test("A direct chat's title has nothing to cut and no count")
    func directTitleParts() {
        let direct = row(Self.direct)
        #expect(direct.titleName == nil)
        #expect(direct.titleCompactCount == nil)
    }

    @Test("One person typing: the name ends where the cut may fall, so 'is typing…' stays whole")
    func typingSplit() {
        let typing = row(Self.group, typing: ["usr_priya_raman"])
        #expect(typing.typingLabel == "Priya Raman is typing…")
        #expect(typing.typingNamesEnd == 11)
        #expect(typing.typingParts == TypingParts(names: "Priya Raman", rest: " is typing…"))
    }

    @Test("Several typing, or nobody: no name to cut")
    func typingWithoutName() {
        let several = row(Self.group, typing: ["usr_priya_raman", "usr_jordan_lee"])
        #expect(several.typingLabel == "Several people are typing…")
        #expect(several.typingNamesEnd == nil)
        #expect(several.typingParts == nil)
        #expect(row(Self.group).typingParts == nil)
    }

    @Test("An emoji or accented name splits on characters, not UTF-16 units")
    func typingSplitByCharacter() {
        let conversation = Sample.conversation(
            #"{"id": 9, "participants": [\#(Sample.me), {"id": "usr_sun", "firstName": "🌻 José", "lastName": "Núñez"}]}"#
        )
        let typing = row(conversation, typing: ["usr_sun"])
        #expect(typing.typingParts?.names == "🌻 José Núñez")
        #expect(typing.typingParts?.rest == " is typing…")
    }

    @Test("A message that never went out says Not sent, and VoiceOver hears it in place of the preview")
    func notSent() {
        let failed = row(Self.direct, failed: true)
        #expect(failed.isSendFailed)
        #expect(failed.accessibilityText.contains("Not sent"))
        #expect(!row(Self.direct).isSendFailed)
    }

    @Test("The list marks a row Not sent while the outbox reports it, and clears it when it goes out")
    func failedSendsFromTheOutbox() async {
        let failed = StateCell<Set<Int>>([])
        let harness = ListHarness(failedSends: failed)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        #expect(harness.row(7)?.isSendFailed == false)
        failed.set([7])
        #expect(await eventually { harness.row(7)?.isSendFailed == true })
        failed.set([])
        #expect(await eventually { harness.row(7)?.isSendFailed == false })
    }

    @Test("Under Unread, a row marked read shows its cleared badge for the removal beat, then leaves")
    func removalBeat() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        harness.model.filter = .unread
        #expect(harness.ids == [63, 90, 7, 41])
        harness.model.markRead(conversationId: 41)
        #expect(harness.row(41)?.unreadCount == 0)
        #expect(harness.ids == [63, 90, 7, 41])
        #expect(
            await eventually {
                harness.clock.advance(by: ChatListModel.removalBeat)
                return harness.row(41) == nil
            }
        )
        #expect(harness.ids == [63, 90, 7])
    }

    @Test("Under All, a row marked read stays where it is")
    func noRemovalUnderAll() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        harness.model.markRead(conversationId: 41)
        harness.clock.advance(by: ChatListModel.removalBeat)
        await settle()
        #expect(harness.row(41)?.unreadCount == 0)
        #expect(harness.ids.count == 5)
    }
}
