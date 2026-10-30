import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ChatFeature

@Suite("Timeline")
struct TimelineTests {
    private let chicago = Fixture.chicago
    private let base = Fixture.base

    private func facts(_ message: ChatMessage) -> GroupingFacts { GroupingFacts(message) }

    private func build(
        _ messages: [ChatMessage],
        pending: [OutgoingMessage] = [],
        viewer: String? = "usr_me",
        days: Bool = true
    ) -> [TimelineItem] {
        TimelineBuilder.build(
            TimelineInput(
                messages: messages,
                pending: pending,
                viewerId: viewer,
                zone: chicago,
                botConversation: false,
                daySeparators: days
            )
        )
    }

    private func rows(_ items: [TimelineItem]) -> [MessageRow] {
        items.compactMap { item in
            if case .message(let row) = item { return row }
            return nil
        }
    }

    // MARK: Grouping (03 §4)

    @Test func sameAuthorWithinFiveMinutesGroups() {
        let first = Fixture.message(1)
        let second = Fixture.message(2, at: base.addingTimeInterval(299))
        #expect(MessageGrouping.canGroup(facts(first), facts(second), zone: chicago))
    }

    @Test func justOverFiveMinutesDoesNotGroup() {
        let second = Fixture.message(2, at: base.addingTimeInterval(301))
        #expect(!MessageGrouping.canGroup(facts(Fixture.message(1)), facts(second), zone: chicago))
    }

    @Test func differentAuthorsDoNotGroup() {
        let second = Fixture.message(2, author: "usr_b", at: base.addingTimeInterval(10))
        #expect(!MessageGrouping.canGroup(facts(Fixture.message(1)), facts(second), zone: chicago))
    }

    @Test func localMidnightSplitsGroups() {
        // 23:58 and 00:01 Chicago time, three minutes apart.
        let before = Fixture.message(1, at: Fixture.instant("2026-10-21T04:58:00Z"))
        let after = Fixture.message(2, at: Fixture.instant("2026-10-21T05:01:00Z"))
        #expect(!MessageGrouping.canGroup(facts(before), facts(after), zone: chicago))
        #expect(MessageGrouping.canGroup(facts(before), facts(after), zone: Fixture.utc))
    }

    @Test func theRepeatedFallBackHourStaysOneLocalDayAndGroups() {
        // DST boundary: 01:58 CDT and 01:02 CST on 2026-11-01 are four minutes apart, same day.
        let beforeChange = Fixture.message(1, at: Fixture.instant("2026-11-01T06:58:00Z"))
        let afterChange = Fixture.message(2, at: Fixture.instant("2026-11-01T07:02:00Z"))
        #expect(MessageGrouping.canGroup(facts(beforeChange), facts(afterChange), zone: chicago))
    }

    @Test func theSpringForwardGapDoesNotSplitTheDay() {
        // DST boundary: 01:58 CST and 03:01 CDT on 2026-03-08 are three minutes apart.
        let before = Fixture.message(1, at: Fixture.instant("2026-03-08T07:58:00Z"))
        let after = Fixture.message(2, at: Fixture.instant("2026-03-08T08:01:00Z"))
        #expect(MessageGrouping.canGroup(facts(before), facts(after), zone: chicago))
    }

    @Test func aSystemMessageBetweenBreaksTheGroup() {
        let items = build(
            [
                Fixture.message(1),
                Fixture.message(2, author: nil, at: base.addingTimeInterval(30), kind: .system),
                Fixture.message(3, at: base.addingTimeInterval(60)),
            ],
            days: false
        )
        let messageRows = rows(items)
        #expect(messageRows.count == 2)
        #expect(messageRows.first?.groupedWithNext == false)
        #expect(messageRows.last?.groupedWithPrevious == false)
        #expect(items.filter { if case .system = $0 { true } else { false } }.count == 1)
    }

    @Test func aThreadReplyNeverGroupsWithItsRoot() {
        let root = Fixture.message(1)
        var reply = Fixture.message(2, at: base.addingTimeInterval(20))
        reply.parentMessageId = 1
        reply.threadRootMessageId = 1
        var sibling = Fixture.message(3, at: base.addingTimeInterval(40))
        sibling.parentMessageId = 1
        sibling.threadRootMessageId = 1
        #expect(!MessageGrouping.canGroup(facts(root), facts(reply), zone: chicago))
        #expect(MessageGrouping.canGroup(facts(reply), facts(sibling), zone: chicago))
    }

    @Test func deletedMessagesDoNotGroup() {
        var deleted = Fixture.message(1)
        deleted.isDeleted = true
        #expect(
            !MessageGrouping.canGroup(
                facts(deleted),
                facts(Fixture.message(2, at: base.addingTimeInterval(5))),
                zone: chicago
            )
        )
    }

    @Test func threeMessagesBySameAuthorShareOneAvatarAndName() {
        let messageRows = rows(
            build([
                Fixture.message(1), Fixture.message(2, at: base.addingTimeInterval(60)),
                Fixture.message(3, at: base.addingTimeInterval(120)),
            ])
        )
        #expect(messageRows.map(\.groupedWithPrevious) == [false, true, true])
        #expect(messageRows.map(\.groupedWithNext) == [true, true, false])
    }

    // MARK: Order and keys (03 §3, §5)

    @Test func ordersByTimeThenIdWithPendingLast() {
        let items = build(
            [Fixture.message(9), Fixture.message(5)],
            pending: [Fixture.outgoing("c-1", state: .queued(attempt: 1), at: base.addingTimeInterval(-60))],
            days: false
        )
        #expect(items.map(\.id) == ["message-5", "message-9", "client-c-1"])
    }

    @Test func alignmentFollowsTheBackendUserId() {
        let messageRows = rows(
            build([
                Fixture.message(1, author: "usr_me"),
                Fixture.message(2, author: "usr_b", at: base.addingTimeInterval(10)),
            ])
        )
        #expect(messageRows.map(\.isMine) == [true, false])
    }

    @Test func anOptimisticRowKeepsItsKeyWhenTheServerCopyLands() {
        let before = build([], pending: [Fixture.outgoing("c-1")], days: false).last?.id
        let after = build([Fixture.message(77, clientId: "c-1")], days: false).last?.id
        #expect(before == after)
        #expect(before == "client-c-1")
    }

    @Test func anOverlappingOutboxRowIsDroppedForItsServerCopy() {
        let items = build([Fixture.message(77, clientId: "c-1")], pending: [Fixture.outgoing("c-1")], days: false)
        #expect(items.count == 1)
        #expect(rows(items).map(\.message.id) == [77])
    }

    @Test func serverMessagesSharingAClientIdAllRender() {
        let items = build(
            [Fixture.message(1, clientId: "dup"), Fixture.message(2, at: base.addingTimeInterval(5), clientId: "dup")],
            days: false
        )
        #expect(items.map(\.id) == ["message-1", "message-2"])
    }

    @Test func pendingRowsGroupWithTheViewersOwnMessages() {
        let items = build(
            [Fixture.message(1, author: "usr_me")],
            pending: [Fixture.outgoing("c-1", at: base.addingTimeInterval(30))],
            days: false
        )
        guard case .pending(let row) = items.last else {
            Issue.record("Expected a pending row")
            return
        }
        #expect(row.groupedWithPrevious)
    }

    // MARK: Day separators and call logs

    @Test func aDaySeparatorPrecedesEachLocalDay() {
        let items = build([
            Fixture.message(1, at: Fixture.instant("2026-10-20T15:00:00Z")),
            Fixture.message(2, at: Fixture.instant("2026-10-21T15:00:00Z")),
        ])
        let days = items.compactMap { item -> ChatDay? in
            if case .day(_, let day) = item { return day }
            return nil
        }
        #expect(days == [ChatDay(year: 2026, month: 10, day: 20), ChatDay(year: 2026, month: 10, day: 21)])
        #expect(items.first?.id == "day-2026-10-20")
    }

    @Test func daySeparatorsCanBeTurnedOff() {
        let items = build([Fixture.message(1)], days: false)
        #expect(!items.contains { if case .day = $0 { true } else { false } })
    }

    @Test func callMessagesCollapseIntoOneCardAtTheNewest() {
        let started = Fixture.system(10, "Video call started", call: 5)
        let between = Fixture.message(11, at: base.addingTimeInterval(60))
        let ended = Fixture.system(12, "Video call ended in 2m", at: base.addingTimeInterval(120), call: 5)
        let items = build([started, between, ended], days: false)
        #expect(items.map(\.id) == ["message-11", "call-5"])
        guard case .callLog(let card) = items.last else {
            Issue.record("Expected a call card")
            return
        }
        #expect(card.messages.map(\.id) == [10, 12])
        #expect(card.summary.duration == "2m")
        #expect(items.last?.contains(messageId: 10) == true)
    }

    // MARK: Reactions (03 §15)

    @Test func reactionsSummariseByEmojiInFirstSeenOrder() {
        let summary = ReactionRules.summarize(
            [
                Reaction(userId: "usr_a", emoji: "👍"), Reaction(userId: "usr_me", emoji: "❤️"),
                Reaction(userId: "usr_b", emoji: " 👍 "), Reaction(userId: "usr_c", emoji: ""),
            ],
            viewerId: "usr_me"
        )
        #expect(summary.map(\.emoji) == ["👍", "❤️"])
        #expect(summary.map(\.count) == [2, 1])
        #expect(summary.map(\.mine) == [false, true])
        #expect(summary.first?.userIds == ["usr_a", "usr_b"])
        #expect(summary.map(\.showsCount) == [true, true], "a count of one still shows")
    }

    @Test func quickReactionsAreTheFixedSix() {
        #expect(ReactionRules.quick == ["👍", "❤️", "😂", "😮", "😢", "😠"])
    }
}
