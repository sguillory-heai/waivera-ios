import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TodayFeature

struct ActivityRulesTests {
    @Test func theSameIdOnTwoPagesRendersOnceUsingTheLaterPage() {
        let first = Fixture.activity(1, summary: "old copy")
        let second = Fixture.activity(2, at: "2026-11-01T15:00:00Z")
        let later = Fixture.activity(1, isRead: true, summary: "new copy")
        let merged = ActivityRules.merge([first, second, later])
        #expect(merged.map(\.id) == [1, 2])
        #expect(merged.first?.summary == "new copy")
        #expect(merged.first?.isRead == true)
    }

    @Test func zonelessUTCTimestampsOrderAsUTCInstantsAgainstZonedOnes() throws {
        // 16:10 written without a zone is UTC, so it is newer than 10:05 CST (16:05 UTC).
        let zoneless = try #require(WaiveraInstant.parse("2026-11-01T16:10:00"))
        let zoned = try #require(WaiveraInstant.parse("2026-11-01T10:05:00-06:00"))
        var newer = Fixture.activity(1)
        newer.createdAt = zoneless
        var older = Fixture.activity(2)
        older.createdAt = zoned
        #expect(ActivityRules.merge([older, newer]).map(\.id) == [1, 2])
    }

    @Test func theRecentActivityFixtureOrdersNewestFirstByParsedInstant() {
        let merged = ActivityRules.merge(DemoData.make().activity.reversed())
        let dates = merged.compactMap(\.createdAt)
        #expect(!merged.isEmpty)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func undatedItemsGoLastThenByIdDescending() {
        let undatedLow = Fixture.activity(3, at: nil)
        let undatedHigh = Fixture.activity(9, at: nil)
        let dated = Fixture.activity(1)
        #expect(ActivityRules.merge([undatedLow, dated, undatedHigh]).map(\.id) == [1, 9, 3])
    }

    @Test func aReactionIsRewrittenWithTheActorAndEmoji() {
        let item = Fixture.activity(1, .reaction, summary: "Dana reacted 🎉 to your message", actor: "Dana", emoji: "🎉")
        #expect(ActivityRules.summary(item) == .reaction(actor: "Dana", emoji: "🎉"))
        #expect(TodayStrings.summary(ActivityRules.summary(item)) == "Dana reacted 🎉 to one of your messages.")
    }

    @Test func aReactionWithoutAnEmojiOrActorStillReadsNaturally() {
        let item = Fixture.activity(1, .reaction, summary: nil, actor: "  ", emoji: nil)
        #expect(ActivityRules.summary(item) == .reaction(actor: nil, emoji: nil))
        #expect(TodayStrings.summary(ActivityRules.summary(item)) == "Someone reacted to one of your messages.")
    }

    @Test func otherTypesUseTheServerSummaryOrTheFallbackWhenItIsBlank() {
        #expect(
            ActivityRules.summary(Fixture.activity(1, .mention, summary: " Jordan mentioned you "))
                == .server("Jordan mentioned you")
        )
        #expect(ActivityRules.summary(Fixture.activity(2, .threadReply, summary: "   ")) == .fallback)
        #expect(TodayStrings.summary(.fallback) == "New chat activity")
    }

    @Test func anUnknownTypeAppearsOnlyUnderAll() {
        #expect(ActivityRules.matches(kind: .unknown, isRead: false, filter: .all, unreadOnly: false))
        for filter in [ActivityFilter.mentions, .replies, .reactions] {
            #expect(!ActivityRules.matches(kind: .unknown, isRead: false, filter: filter, unreadOnly: false))
        }
    }

    @Test func typeChipsAndTheUnreadToggleCombineWithAnd() {
        #expect(ActivityRules.matches(kind: .mention, isRead: false, filter: .mentions, unreadOnly: true))
        #expect(!ActivityRules.matches(kind: .mention, isRead: true, filter: .mentions, unreadOnly: true))
        #expect(!ActivityRules.matches(kind: .reaction, isRead: false, filter: .mentions, unreadOnly: true))
        #expect(ActivityRules.matches(kind: .reaction, isRead: true, filter: .reactions, unreadOnly: false))
        #expect(ActivityRules.matches(kind: .threadReply, isRead: false, filter: .replies, unreadOnly: false))
    }

    @Test func searchMatchesTheShownTextOrTheActorIgnoringCase() {
        #expect(ActivityRules.matches(query: "", summaryText: "anything", actor: nil))
        #expect(ActivityRules.matches(query: "  forms ", summaryText: "I'll bring the FORMS.", actor: nil))
        #expect(ActivityRules.matches(query: "dana", summaryText: "Someone reacted", actor: "Dana Kim"))
        #expect(!ActivityRules.matches(query: "meds", summaryText: "I'll bring the forms.", actor: "Sam"))
    }

    @Test func olderPagesMayHoldUnreadOnlyWhenTheOldestLoadedPageHasUnreadAndMoreExist() {
        let readPage = (1...30).map { Fixture.activity(Int64($0), isRead: true) }
        var lastUnread = readPage
        lastUnread[29].isRead = false
        let isRead: (ActivityItem) -> Bool = { $0.isRead }
        #expect(ActivityRules.olderPagesMayHoldUnread(lastUnread, hasMore: true, isRead: isRead))
        #expect(!ActivityRules.olderPagesMayHoldUnread(lastUnread, hasMore: false, isRead: isRead))
        #expect(!ActivityRules.olderPagesMayHoldUnread(readPage, hasMore: true, isRead: isRead))
        // Only the oldest page counts: unread on page 1 of two says nothing about page 3.
        let twoPages = lastUnread.reversed() + (31...60).map { Fixture.activity(Int64($0), isRead: true) }
        #expect(!ActivityRules.olderPagesMayHoldUnread(Array(twoPages), hasMore: true, isRead: isRead))
    }
}
