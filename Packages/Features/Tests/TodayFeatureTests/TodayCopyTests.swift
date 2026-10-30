import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import TodayFeature

/// The copy rows show: placeholders, plurals, time phrases and the quiet line. Formatting runs
/// on wall-clock values already in the saved zone, so the device zone never matters.
struct TodayCopyTests {
    private let formatter = TodayFormatter(locale: Locale(identifier: "en_US_POSIX"))

    @Test func placeholdersFillInOrderAndByPosition() {
        #expect(TodayStrings.fill("%@ and %ld", ["A", "2"]) == "A and 2")
        #expect(TodayStrings.fill("%2$@ before %1$@", ["one", "two"]) == "two before one")
        #expect(TodayStrings.fill("100%% sure, %@", ["Sam"]) == "100% sure, Sam")
        #expect(TodayStrings.fill("%@ and %@", ["only"]) == "only and ")
    }

    @Test func everyKeyResolvesToCopyNotItsKey() {
        let keys = [
            "today.title", "activity.title", "today.caughtUp.title", "today.quiet.offline", "today.toast.refreshFailed",
            "today.activity.markAllRead", "today.activity.clearFilters", "today.activity.search", "today.retry",
        ]
        for key in keys {
            #expect(TodayStrings.text(key) != key, "missing copy for \(key)")
        }
    }

    @Test func pluralsPickOneOrOther() {
        #expect(TodayStrings.unreadMessages(1) == "1 unread message")
        #expect(TodayStrings.unreadMessages(3) == "3 unread messages")
        #expect(TodayStrings.unreadUpdates(1, lowerBound: false) == "1 unread update")
        #expect(TodayStrings.unreadUpdates(150, lowerBound: true) == "150 or more unread updates")
        #expect(TodayStrings.showMore(2) == "Show 2 more")
    }

    @Test func celebrationsReadAsOneSentence() {
        let both = CelebrationItem(userId: "u1", name: "Jordan Lee", isBirthday: true, anniversaryYears: 5)
        #expect(TodayStrings.celebration(both) == "Happy birthday and 5-year work anniversary, Jordan Lee!")
        let anniversary = CelebrationItem(userId: "u2", name: nil, isBirthday: false, anniversaryYears: 1)
        #expect(TodayStrings.celebration(anniversary) == "Happy 1-year work anniversary, Teammate!")
    }

    @Test func snippetsNeverShowRawPlaceholders() {
        #expect(TodayStrings.snippet(.photo) == "Photo")
        #expect(TodayStrings.snippet(.file(name: nil)) == "File attachment")
        #expect(TodayStrings.snippet(.file(name: "rota.pdf")) == "rota.pdf")
        #expect(TodayStrings.joined("Priya", nil) == "Priya")
        #expect(TodayStrings.joined("Priya", "Photo") == "Priya · Photo")
        #expect(TodayStrings.spoken("Priya", nil, "", "2 unread messages") == "Priya, 2 unread messages")
    }

    @Test func clockTimesAreTwelveHourWhateverTheDeviceZone() {
        #expect(formatter.time(ClockTime(hour: 0, minute: 30)) == "12:30 AM")
        #expect(formatter.time(ClockTime(hour: 13, minute: 5)) == "1:05 PM")
        #expect(formatter.day(Fixture.date(2026, 10, 31)) == "Sat, Oct 31")
        #expect(formatter.longDay(Fixture.date(2026, 11, 1)) == "Sunday, November 1")
    }

    @Test func upcomingLabelsReadNaturally() {
        #expect(formatter.upcoming(.inMinutes(0)) == "Starting now")
        #expect(formatter.upcoming(.inMinutes(25)) == "in 25 min")
        #expect(formatter.upcoming(.inHours(2, minutes: 0)) == "in 2 hr")
        #expect(formatter.upcoming(.inHours(1, minutes: 30)) == "in 1 hr 30 min")
        #expect(formatter.upcoming(.now(until: ClockTime(hour: 11, minute: 0))) == "Now · until 11:00 AM")
        #expect(formatter.upcoming(.tomorrowAt(ClockTime(hour: 9, minute: 0))) == "Tomorrow · 9:00 AM")
        #expect(
            formatter.upcoming(.onDayAt(Fixture.date(2026, 11, 4), ClockTime(hour: 9, minute: 0)))
                == "Wed, Nov 4 · 9:00 AM"
        )
        #expect(formatter.upcoming(.allDayToday) == "All day today")
    }

    @Test func rangesSayWhenAnItemEndsTheNextDay() {
        let shift = NextUpItem(
            eventId: "s",
            title: nil,
            time: .inHours(1, minutes: 0),
            start: ClockTime(hour: 22, minute: 0),
            end: ClockTime(hour: 6, minute: 0),
            endsOnLaterDay: true,
            location: nil,
            isOnline: false
        )
        #expect(formatter.range(shift) == "10:00 PM – 6:00 AM next day")
        var allDay = shift
        allDay.start = nil
        #expect(formatter.range(allDay) == nil)
    }

    @Test func pastLabelsAreCompactOnScreenAndFullWhenSpoken() {
        #expect(formatter.past(.minutesAgo(5)) == "5m")
        #expect(formatter.pastSpoken(.minutesAgo(5)) == "5 minutes ago")
        #expect(formatter.pastSpoken(.minutesAgo(1)) == "1 minute ago")
        #expect(formatter.past(.todayAt(ClockTime(hour: 9, minute: 12))) == "9:12 AM")
        #expect(formatter.past(.onDate(Fixture.date(2026, 10, 31))) == "Sat, Oct 31")
    }

    @Test func theQuietLineSaysOfflineOrHowOldTheDataIs() {
        #expect(formatter.quiet(.stale(since: .minutesAgo(12))) == "Updated 12 min ago")
        #expect(formatter.quiet(.stale(since: .todayAt(ClockTime(hour: 8, minute: 2)))) == "Updated at 8:02 AM")
        #expect(formatter.quiet(.offline(since: nil)) == "You're offline. Showing saved updates.")
        #expect(formatter.quiet(.offline(since: .yesterday)) == "You're offline · updated yesterday")
    }

    @Test func toastsUseFixedCopyNeverServerText() {
        #expect(TodayNotice.refreshFailed.message == "Couldn't refresh. Showing saved updates.")
        #expect(TodayNotice.invitationAnswered(accept: false).message == "Invitation declined")
        #expect(!TodayNotice.invitationAnswered(accept: true).offersRetry)
        #expect(TodayNotice.markReadFailed(activityId: 1).offersRetry)
    }

    @Test func theDisplayClockSplitsTheTimeFromItsPeriodAndTheTrackHoursDropTheirs() {
        let eleven = ClockTime(hour: 11, minute: 0)
        let afternoon = ClockTime(hour: 14, minute: 30)
        #expect(formatter.clock(eleven) == "11:00")
        #expect(formatter.meridiem(eleven) == "AM")
        #expect(formatter.clock(afternoon) == "2:30")
        #expect(formatter.meridiem(afternoon) == "PM")
        #expect(formatter.hour(ClockTime(hour: 8, minute: 0), withPeriod: true) == "8 AM")
        #expect(formatter.hour(ClockTime(hour: 10, minute: 0), withPeriod: false) == "10")
        #expect(formatter.hour(ClockTime(hour: 0, minute: 0), withPeriod: true) == "12 AM")
    }

    @Test func theRewardBurstPlaysOncePerDay() {
        #expect(RewardBurst.plays(today: "2026-11-01", lastPlayed: ""))
        #expect(!RewardBurst.plays(today: "2026-11-01", lastPlayed: "2026-11-01"))
        #expect(RewardBurst.plays(today: "2026-11-02", lastPlayed: "2026-11-01"))
        #expect(!RewardBurst.plays(today: "", lastPlayed: ""), "no day yet: nothing to celebrate")
        #expect(RewardBurst.seed(nil) == 0)
        #expect(RewardBurst.seed(Fixture.date(2026, 11, 2)) == RewardBurst.seed(Fixture.date(2026, 11, 1)) + 1)
    }
}
