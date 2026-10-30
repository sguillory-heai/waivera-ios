import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ChatFeature

/// Inside a conversation, times and day separators follow the employee's saved zone, as the chat
/// list does, not the device zone (PF-08).
@MainActor
@Suite("Chat clock zone", .serialized)
struct ChatClockZoneTests {
    @Test func theConversationClockUsesTheEmployeesSavedZone() async {
        let harness = await ModelHarness()
        let clock = ChatClock.employee(harness.fakes.environment)
        let saved = harness.fakes.environment.calendar.scheduleTimeZone().zone
        #expect(clock.timeZone.identifier == saved.identifier)
        #expect(clock.timeZone.identifier == "America/Chicago")
    }

    @Test func daySeparatorsFollowTheSavedZoneAcrossTheFallBack() async {
        let harness = await ModelHarness()
        let zone = ChatClock.employee(harness.fakes.environment).timeZone
        // DST boundary: 23:30 CDT on 31 Oct and 01:30 CST on 1 Nov, after Chicago falls back.
        // Both are 1 Nov in UTC, so a device in UTC would draw one separator; the saved zone
        // draws two.
        let late = Fixture.message(1, at: Fixture.instant("2026-11-01T04:30:00Z"))
        let afterFallBack = Fixture.message(2, at: Fixture.instant("2026-11-01T07:30:00Z"))
        func days(in zone: TimeZone) -> [ChatDay] {
            TimelineBuilder.build(
                TimelineInput(
                    messages: [late, afterFallBack],
                    pending: [],
                    viewerId: "usr_me",
                    zone: zone,
                    botConversation: false,
                    daySeparators: true
                )
            ).compactMap { item -> ChatDay? in
                if case .day(_, let day) = item { return day }
                return nil
            }
        }
        #expect(days(in: zone) == [ChatDay(year: 2026, month: 10, day: 31), ChatDay(year: 2026, month: 11, day: 1)])
        #expect(days(in: Fixture.utc) == [ChatDay(year: 2026, month: 11, day: 1)])
    }
}
