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
        let rig = harness(feed: CalendarFeed(events: [event("e1", "2026-10-27T16:00:00Z", "2026-10-27T17:00:00Z")]))
        rig.calendar.holds.update { $0 = true }
        #expect(rig.model.state.agenda == .loading)
        await running(rig.model) {
            #expect(await eventually { rig.calendar.calls.count("refresh:month") == 1 })
            #expect(rig.model.state.agenda == .loading)
            rig.calendar.release()
            #expect(await eventually { isContent(rig.model.state.agenda) })
        }
        guard case .content(let rows) = rig.model.state.agenda else { return }
        #expect(rows.map(\.id) == ["event:e1"])
    }

    @Test func emptyDayAfterASyncIsEmptyAndTheWholeMonthGridIsRequested() async {
        let rig = harness()
        await running(rig.model) {
            #expect(await eventually { rig.model.state.agenda == .empty })
        }
        // The October grid starts on Sunday 27 September.
        #expect(rig.calendar.calls.all.contains("refresh:month:2026-09-27"))
        #expect(rig.model.state.cells.count == 42)
        #expect(rig.model.state.title == "October 2026")
        #expect(rig.model.state.agendaHeading == "Tuesday, October 27")
    }

    @Test func spillDayEventsGetDotsBecauseTheGridRangeIsFetched() async {
        let rig = harness(feed: CalendarFeed(events: [event("spill", "2026-11-06T15:00:00Z", "2026-11-06T16:00:00Z")]))
        let spillDay = day(2026, 11, 6)
        await running(rig.model) {
            #expect(await eventually { rig.model.state.cells.first { $0.date == spillDay }?.marker.events == 1 })
        }
        let cell = rig.model.state.cells.first { $0.date == day(2026, 11, 6) }
        #expect(cell?.inPeriod == false)
    }

    @Test func coldFailureShowsTheErrorAndRetryRecovers() async {
        let rig = harness()
        rig.calendar.failure.update { $0 = .server(statusCode: 503) }
        await running(rig.model) {
            #expect(await eventually { rig.model.state.agenda == .error(.server(statusCode: 503)) })
            #expect(rig.model.state.feedNotice == nil)
            rig.calendar.failure.update { $0 = nil }
            rig.model.retry()
            #expect(await eventually { rig.model.state.agenda == .empty })
        }
    }

    @Test func failedRefreshOverSavedDataKeepsTheAgendaAndShowsABanner() async {
        let rig = harness(feed: CalendarFeed(events: [event("e1", "2026-10-27T16:00:00Z", "2026-10-27T17:00:00Z")]))
        await running(rig.model) {
            #expect(await eventually { isContent(rig.model.state.agenda) })
            rig.calendar.failure.update { $0 = .offline }
            await rig.model.refresh()
            #expect(await eventually { rig.model.state.feedNotice != nil })
            #expect(isContent(rig.model.state.agenda))
            #expect(rig.model.state.feedNotice == "Couldn't refresh your schedule. Showing what was saved.")
            rig.realtime.bannerCell.set(.offline)
            #expect(await eventually { rig.model.state.feedNotice == "You're offline. Showing your saved schedule." })
        }
    }

    /// Calendar has no hub events; the data layer refetches every observed feed and the
    /// milestones on reconnect, so the screen must not fetch a second time.
    @Test func reconnectLeavesTheResyncToTheDataLayer() async {
        let rig = harness()
        await running(rig.model) {
            #expect(await eventually { rig.model.state.agenda == .empty })
            let feedRefreshes = rig.calendar.calls.count("refresh:")
            let milestoneRefreshes = rig.calendar.calls.count("milestones")
            rig.realtime.status.set(RealtimeStatus(state: .reconnecting(attempt: 1, delay: .seconds(1)), epoch: 1))
            try? await Task.sleep(for: .milliseconds(20))
            #expect(rig.calendar.calls.count("refresh:") == feedRefreshes)
            rig.realtime.status.set(RealtimeStatus(state: .connected, epoch: 2))
            try? await Task.sleep(for: .milliseconds(30))
            #expect(rig.calendar.calls.count("refresh:") == feedRefreshes)
            #expect(rig.calendar.calls.count("milestones") == milestoneRefreshes)
        }
    }

    @Test func todayIsTheEmployeesDateNotTheDevicesOnTheFallBackNight() async {
        // 23:30 CST on 1 Nov 2026 is 2 Nov in Tokyo and in UTC.
        let rig = harness(now: instant("2026-11-02T05:30:00Z"), deviceZone: Zones.tokyo)
        #expect(rig.model.today == day(2026, 11, 1))
        #expect(rig.model.state.cells.first { $0.isToday }?.date == day(2026, 11, 1))
        #expect(rig.model.state.zoneNotice?.hasPrefix("Times shown in") == true)
        #expect(rig.model.state.isTodaySelected)
        let today = rig.model.state.cells.first { $0.isToday }
        #expect(today?.isSelected == true)
    }

    @Test func noSavedZoneUsesChicagoAndSaysSo() {
        let rig = harness(now: instant("2026-11-02T05:30:00Z"), savedZone: nil, deviceZone: Zones.tokyo)
        #expect(rig.model.scheduleZone.identifier == "America/Chicago")
        #expect(rig.model.today == day(2026, 11, 1))
        #expect(rig.model.state.zoneNotice?.hasPrefix("Your profile has no time zone") == true)
    }

    @Test func changingTheSavedZoneMovesTodayAndRefetches() async {
        let rig = harness(now: instant("2026-11-01T14:30:00Z"))
        await running(rig.model) {
            #expect(await eventually { rig.model.state.agenda == .empty })
            #expect(rig.model.today == day(2026, 11, 1))
            let before = rig.model.feedKey
            rig.session.cell.set(
                .signedIn(CurrentUser(id: "usr_me", firebaseUid: "fb", timeZoneIdentifier: "Asia/Tokyo"))
            )
            #expect(await eventually { rig.model.today == day(2026, 11, 1) && rig.model.feedKey != before })
            #expect(rig.model.scheduleZone.identifier == "Asia/Tokyo")
        }
    }

    @Test func weekStepRequestsTheNextSevenDays() async {
        let rig = harness()
        await running(rig.model) {
            rig.model.select(view: .week)
            #expect(await eventually { rig.calendar.calls.all.contains("refresh:week:2026-10-25") })
            rig.model.step(1)
            #expect(rig.model.selectedDate == day(2026, 11, 3))
            #expect(rig.model.state.title == "November 1–7, 2026")
            #expect(await eventually { rig.calendar.calls.all.contains("refresh:week:2026-11-01") })
        }
    }

    @Test func switchingViewsKeepsTheSelectedDate() {
        let rig = harness()
        rig.model.select(date: day(2026, 10, 14))
        rig.model.select(view: .day)
        #expect(rig.model.selectedDate == day(2026, 10, 14))
        #expect(rig.model.state.cells.isEmpty)
        #expect(rig.model.state.title == "Wed, October 14")
        rig.model.select(view: .week)
        #expect(rig.model.state.cells.count == 7)
        #expect(rig.model.state.cells.first { $0.isSelected }?.date == day(2026, 10, 14))
    }

    @Test func todayButtonReturnsToTodayInTheSavedZone() {
        let rig = harness()
        rig.model.step(1)
        rig.model.step(1)
        #expect(rig.model.selectedDate == day(2026, 12, 27))
        rig.model.goToToday()
        #expect(rig.model.selectedDate == day(2026, 10, 27))
        #expect(rig.model.state.isTodaySelected)
    }

    @Test func resumeAfterMidnightMovesToday() {
        let rig = harness(now: instant("2026-10-28T04:50:00Z"))
        #expect(rig.model.today == day(2026, 10, 27))
        rig.clock.advance(by: 20 * 60)
        rig.model.resume()
        #expect(rig.model.today == day(2026, 10, 28))
        #expect(rig.model.state.agendaHeading == "Wednesday, October 28")
    }
}
