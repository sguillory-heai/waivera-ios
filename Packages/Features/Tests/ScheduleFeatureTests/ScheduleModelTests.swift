import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ScheduleFeature

@MainActor
@Suite("Schedule model", .serialized)
struct ScheduleModelTests {
    /// 10:00 CDT on Tuesday 27 Oct 2026.
    let morning = instant("2026-10-27T15:00:00Z")

    struct Harness {
        let clock: ManualClock
        let calendar: TestCalendarRepository
        let session: TestSession
        let realtime: TestRealtime
        let model: ScheduleModel
    }

    func harness(
        now: Date? = nil,
        feed: CalendarFeed = CalendarFeed(),
        milestones: [Milestone] = [],
        savedZone: String? = "America/Chicago",
        deviceZone: TimeZone = Zones.chicago
    ) -> Harness {
        let clock = ManualClock(now: now ?? morning)
        let zone = ScheduleZone.resolve(savedIdentifier: savedZone).timeZone
        let calendar = TestCalendarRepository(
            zone: zone,
            today: CalendarDate(clock.now, in: zone),
            feed: feed,
            milestones: milestones,
            clock: clock
        )
        let session = TestSession.signedIn(zone: savedZone)
        let realtime = TestRealtime()
        let model = ScheduleModel(
            calendar: calendar,
            session: session,
            realtime: realtime,
            clock: clock,
            deviceZone: { deviceZone },
            locale: english
        )
        return Harness(
            clock: clock,
            calendar: calendar,
            session: session,
            realtime: realtime,
            model: model
        )
    }

    /// Runs the view's two tasks for the duration of `body`.
    func running(_ model: ScheduleModel, _ body: () async throws -> Void) async rethrows {
        let start = Task { await model.start() }
        var feedKey = model.feedKey
        var feed = Task { await model.observeFeed() }
        let follower = Task { @MainActor in
            while !Task.isCancelled {
                if model.feedKey != feedKey {
                    feed.cancel()
                    feedKey = model.feedKey
                    feed = Task { await model.observeFeed() }
                }
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
        defer {
            follower.cancel()
            feed.cancel()
            start.cancel()
        }
        try await body()
    }

    func isContent(_ state: AgendaState) -> Bool {
        if case .content = state { return true }
        return false
    }

    @Test func loadingUntilTheFirstRefreshLandsThenContent() async {
        let h = harness(feed: CalendarFeed(events: [event("e1", "2026-10-27T16:00:00Z", "2026-10-27T17:00:00Z")]))
        h.calendar.holds.update { $0 = true }
        #expect(h.model.state.agenda == .loading)
        await running(h.model) {
            #expect(await eventually { h.calendar.calls.count("refresh:month") == 1 })
            #expect(h.model.state.agenda == .loading)
            h.calendar.release()
            #expect(await eventually { isContent(h.model.state.agenda) })
        }
        guard case .content(let rows) = h.model.state.agenda else { return }
        #expect(rows.map(\.id) == ["event:e1"])
    }

    @Test func emptyDayAfterASyncIsEmptyAndTheWholeMonthGridIsRequested() async {
        let h = harness()
        await running(h.model) {
            #expect(await eventually { h.model.state.agenda == .empty })
        }
        // The October grid starts on Sunday 27 September.
        #expect(h.calendar.calls.all.contains("refresh:month:2026-09-27"))
        #expect(h.model.state.cells.count == 42)
        #expect(h.model.state.title == "October 2026")
        #expect(h.model.state.agendaHeading == "Tuesday, October 27")
    }

    @Test func spillDayEventsGetDotsBecauseTheGridRangeIsFetched() async {
        let h = harness(feed: CalendarFeed(events: [event("spill", "2026-11-06T15:00:00Z", "2026-11-06T16:00:00Z")]))
        await running(h.model) {
            #expect(await eventually { h.model.state.cells.first { $0.date == day(2026, 11, 6) }?.marker.events == 1 })
        }
        let cell = h.model.state.cells.first { $0.date == day(2026, 11, 6) }
        #expect(cell?.inPeriod == false)
    }

    @Test func coldFailureShowsTheErrorAndRetryRecovers() async {
        let h = harness()
        h.calendar.failure.update { $0 = .server(statusCode: 503) }
        await running(h.model) {
            #expect(await eventually { h.model.state.agenda == .error(.server(statusCode: 503)) })
            #expect(h.model.state.feedNotice == nil)
            h.calendar.failure.update { $0 = nil }
            h.model.retry()
            #expect(await eventually { h.model.state.agenda == .empty })
        }
    }

    @Test func failedRefreshOverSavedDataKeepsTheAgendaAndShowsABanner() async {
        let h = harness(feed: CalendarFeed(events: [event("e1", "2026-10-27T16:00:00Z", "2026-10-27T17:00:00Z")]))
        await running(h.model) {
            #expect(await eventually { isContent(h.model.state.agenda) })
            h.calendar.failure.update { $0 = .offline }
            await h.model.refresh()
            #expect(await eventually { h.model.state.feedNotice != nil })
            #expect(isContent(h.model.state.agenda))
            #expect(h.model.state.feedNotice == "Couldn't refresh your schedule. Showing what was saved.")
            h.realtime.bannerCell.set(.offline)
            #expect(await eventually { h.model.state.feedNotice == "You're offline. Showing your saved schedule." })
        }
    }

    /// Calendar has no hub events; the data layer refetches every observed feed and the
    /// milestones on reconnect, so the screen must not fetch a second time.
    @Test func reconnectLeavesTheResyncToTheDataLayer() async {
        let h = harness()
        await running(h.model) {
            #expect(await eventually { h.model.state.agenda == .empty })
            let feedRefreshes = h.calendar.calls.count("refresh:")
            let milestoneRefreshes = h.calendar.calls.count("milestones")
            h.realtime.status.set(RealtimeStatus(state: .reconnecting(attempt: 1, delay: .seconds(1)), epoch: 1))
            try? await Task.sleep(for: .milliseconds(20))
            #expect(h.calendar.calls.count("refresh:") == feedRefreshes)
            h.realtime.status.set(RealtimeStatus(state: .connected, epoch: 2))
            try? await Task.sleep(for: .milliseconds(30))
            #expect(h.calendar.calls.count("refresh:") == feedRefreshes)
            #expect(h.calendar.calls.count("milestones") == milestoneRefreshes)
        }
    }

    @Test func todayIsTheEmployeesDateNotTheDevicesOnTheFallBackNight() async {
        // 23:30 CST on 1 Nov 2026 is 2 Nov in Tokyo and in UTC.
        let h = harness(now: instant("2026-11-02T05:30:00Z"), deviceZone: Zones.tokyo)
        #expect(h.model.today == day(2026, 11, 1))
        #expect(h.model.state.cells.first { $0.isToday }?.date == day(2026, 11, 1))
        #expect(h.model.state.zoneNotice?.hasPrefix("Times shown in") == true)
        #expect(h.model.state.isTodaySelected)
        let today = h.model.state.cells.first { $0.isToday }
        #expect(today?.isSelected == true)
    }

    @Test func noSavedZoneUsesChicagoAndSaysSo() {
        let h = harness(now: instant("2026-11-02T05:30:00Z"), savedZone: nil, deviceZone: Zones.tokyo)
        #expect(h.model.scheduleZone.identifier == "America/Chicago")
        #expect(h.model.today == day(2026, 11, 1))
        #expect(h.model.state.zoneNotice?.hasPrefix("Your profile has no time zone") == true)
    }

    @Test func changingTheSavedZoneMovesTodayAndRefetches() async {
        let h = harness(now: instant("2026-11-01T14:30:00Z"))
        await running(h.model) {
            #expect(await eventually { h.model.state.agenda == .empty })
            #expect(h.model.today == day(2026, 11, 1))
            let before = h.model.feedKey
            h.session.cell.set(
                .signedIn(CurrentUser(id: "usr_me", firebaseUid: "fb", timeZoneIdentifier: "Asia/Tokyo"))
            )
            #expect(await eventually { h.model.today == day(2026, 11, 1) && h.model.feedKey != before })
            #expect(h.model.scheduleZone.identifier == "Asia/Tokyo")
        }
    }

    @Test func weekStepRequestsTheNextSevenDays() async {
        let h = harness()
        await running(h.model) {
            h.model.select(view: .week)
            #expect(await eventually { h.calendar.calls.all.contains("refresh:week:2026-10-25") })
            h.model.step(1)
            #expect(h.model.selectedDate == day(2026, 11, 3))
            #expect(h.model.state.title == "November 1–7, 2026")
            #expect(await eventually { h.calendar.calls.all.contains("refresh:week:2026-11-01") })
        }
    }

    @Test func switchingViewsKeepsTheSelectedDate() {
        let h = harness()
        h.model.select(date: day(2026, 10, 14))
        h.model.select(view: .day)
        #expect(h.model.selectedDate == day(2026, 10, 14))
        #expect(h.model.state.cells.isEmpty)
        #expect(h.model.state.title == "Wed, October 14")
        h.model.select(view: .week)
        #expect(h.model.state.cells.count == 7)
        #expect(h.model.state.cells.first { $0.isSelected }?.date == day(2026, 10, 14))
    }

    @Test func todayButtonReturnsToTodayInTheSavedZone() {
        let h = harness()
        h.model.step(1)
        h.model.step(1)
        #expect(h.model.selectedDate == day(2026, 12, 27))
        h.model.goToToday()
        #expect(h.model.selectedDate == day(2026, 10, 27))
        #expect(h.model.state.isTodaySelected)
    }

    @Test func resumeAfterMidnightMovesToday() {
        let h = harness(now: instant("2026-10-28T04:50:00Z"))
        #expect(h.model.today == day(2026, 10, 27))
        h.clock.advance(by: 20 * 60)
        h.model.resume()
        #expect(h.model.today == day(2026, 10, 28))
        #expect(h.model.state.agendaHeading == "Wednesday, October 28")
    }
}
