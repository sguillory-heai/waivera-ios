import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import WaiveraTestSupport

@Suite("Demo data")
struct DemoDataTests {
    let data = DemoData.make()

    @Test func todayIsTheFallBackDayInChicago() {
        #expect(DemoData.today == CalendarDate(year: 2026, month: 11, day: 1))
        #expect(DemoData.today.interval(in: DemoData.timeZone).duration == 25 * 3_600)
        #expect(data.user.scheduleTimeZone.identifier == "America/Chicago")
        #expect(data.user.organization?.id == 12)
    }

    @Test func inboxVariety() throws {
        let kinds = Set(data.conversations.map(\.kind))
        #expect(kinds == [.direct, .channel, .group, .bot])
        #expect(data.conversations.filter { $0.unreadCount > 0 }.count >= 3)
        #expect(data.conversations.contains { !$0.canWrite })
        let bot = try #require(data.conversations.first { $0.kind == .bot })
        #expect(bot.lastMessage?.ticket?.ticketId == "T-1042")
    }

    @Test func timelineVariety() throws {
        let direct = try #require(data.messages[7])
        #expect(direct.contains { $0.attachment != nil })
        #expect(direct.contains { !$0.reactions.isEmpty })
        #expect(direct.contains { $0.threadReplyCount > 0 })
        #expect(direct.contains { $0.kind == .system })
        #expect(direct.filter(\.isCallLog).count == 2)
        #expect(direct.allSatisfy { !$0.isThreadReply })
        #expect(direct == direct.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
        let group = try #require(data.messages[63])
        #expect(group.last?.reactions.count == 2)
        #expect(group.contains { $0.isMine })
        #expect(data.messages[90]?.first?.ticket != nil)
    }

    @Test func threadAndFailedSend() throws {
        let thread = try #require(data.threads[9330])
        #expect(thread.root?.id == 9330)
        #expect(thread.replies.count >= 2)
        #expect(data.pending.first?.isFailed == true)
        #expect(data.pending.first?.conversationId == 7)
    }

    @Test func calendarToday() throws {
        let agenda = data.calendar.agenda(
            on: DemoData.today,
            in: DemoData.timeZone,
            celebrations: MilestoneIndex(data.milestones).celebrations(on: DemoData.today)
        )
        #expect(agenda.events.contains { $0.isAllDay })
        let overnight = try #require(agenda.events.first { $0.id == "evt_demo_overnight" })
        // 00:30 CDT to 01:30 CST reads as one hour on the clock but lasts two.
        #expect(overnight.end.timeIntervalSince(overnight.start) == 2 * 3_600)
        #expect(agenda.events.first { $0.id == "evt_demo_invite" }?.needsResponse(at: DemoData.now) == true)
        #expect(agenda.events.first { $0.id == "evt_demo_checkin" }?.joinURL != nil)
        #expect(agenda.celebrations.map(\.kind).contains(.birthday))
        #expect(agenda.celebrations.contains { $0.anniversaryYears == 5 })
        #expect(data.calendar.holidays.isEmpty == false)
        #expect(data.calendar.timeOff.isEmpty == false)
    }

    @Test func activityBookmarksPeopleAndProfile() {
        #expect(data.activity.count == 3)
        #expect(data.bookmarks.isEmpty == false)
        #expect(data.directory.map(\.name) == data.directory.map(\.name).sorted())
        #expect(data.people["usr_alex_rivera"]?.displayName == "Alex Rivera")
        #expect(data.profile.profile != nil)
        #expect(data.profile.timeOff != nil)
        #expect(data.profile.files.count == 1)
    }

    @Test func emptyKeepsOnlyTheUser() {
        let empty = DemoData.empty
        #expect(empty.conversations.isEmpty)
        #expect(empty.calendar.isEmpty)
        #expect(empty.user.id == DemoData.viewerId)
    }
}
