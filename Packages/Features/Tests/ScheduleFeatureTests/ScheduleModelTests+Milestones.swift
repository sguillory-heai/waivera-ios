import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraRealtime
import WaiveraTestSupport

@testable import ScheduleFeature

/// Milestones, pull to refresh, range memory and the demo environment.
@MainActor
extension ScheduleModelTests {
    @Test func staleMilestonesRefreshOnOpenButFreshOnesDoNot() async {
        let fresh = harness()
        fresh.calendar.milestoneCell.set(Resource(value: .empty, phase: .loaded, updatedAt: fresh.clock.now))
        await running(fresh.model) {
            #expect(await eventually { fresh.model.state.agenda == .empty })
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(fresh.calendar.calls.count("milestones") == 0)

        let stale = harness()
        stale.calendar.milestoneCell.set(
            Resource(value: .empty, phase: .loaded, updatedAt: stale.clock.now.addingTimeInterval(-16 * 60))
        )
        await running(stale.model) {
            #expect(await eventually { stale.calendar.calls.count("milestones") == 1 })
        }
    }

    @Test func milestoneFailureIsSurfacedWithoutHidingTheAgenda() async {
        let h = harness(feed: CalendarFeed(events: [event("e1", "2026-10-27T16:00:00Z", "2026-10-27T17:00:00Z")]))
        h.calendar.milestoneFailure.update { $0 = .server(statusCode: 500) }
        await running(h.model) {
            #expect(await eventually { isContent(h.model.state.agenda) })
            #expect(await eventually { h.model.state.milestonesFailed })
        }
    }

    @Test func milestonesAppearOnTheGridAndInTheAgenda() async {
        let h = harness(milestones: [
            Milestone(kind: .birthday, userId: "u1", displayName: "Jordan Lee", month: 10, day: 27),
            Milestone(
                kind: .workAnniversary,
                userId: "u2",
                displayName: "Sam Ortiz",
                month: 10,
                day: 30,
                startYear: 2021
            ),
        ])
        await running(h.model) {
            #expect(await eventually { isContent(h.model.state.agenda) })
        }
        #expect(h.model.state.cells.first { $0.date == day(2026, 10, 30) }?.marker.celebrations == 1)
        guard case .content(let rows) = h.model.state.agenda else { return }
        #expect(rows.first?.title == "It's Jordan Lee's birthday today!")
        #expect(rows.first?.accessibilityLabel == "Jordan Lee is celebrating a birthday today.")
    }

    @Test func pullToRefreshRefreshesFeedAndMilestonesTogether() async {
        let h = harness()
        await h.model.refresh()
        #expect(h.calendar.calls.count("refresh:month") == 1)
        #expect(h.calendar.calls.count("milestones") == 1)
    }

    @Test func eventsSeenOnTheScheduleAreRememberedForTheEventScreen() async {
        let h = harness(feed: CalendarFeed(events: [event("e1", "2026-10-29T16:00:00Z", "2026-10-29T17:00:00Z")]))
        await running(h.model) {
            #expect(await eventually { h.memory.entry(for: "e1") != nil })
        }
        #expect(h.memory.entry(for: "e1") == EventRangeMemory.Entry(view: .month, anchor: day(2026, 10, 27)))
    }

    @Test func freshFeedIsNotRefetchedOnAppearance() async {
        let h = harness()
        let fresh = Resource(value: CalendarFeed(), phase: .loaded, updatedAt: h.clock.now)
        h.calendar.cell(.month, day(2026, 10, 27)).set(fresh)
        await running(h.model) {
            #expect(await eventually { h.model.state.agenda == .empty })
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(h.calendar.calls.count("refresh:") == 0)
    }

    @Test func demoEnvironmentRendersTodaysAgendaOnTheFallBackDay() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        await fake.environment.launch()
        let model = ScheduleModel(
            calendar: fake.calendar,
            session: fake.session,
            realtime: fake.realtimeStatus,
            clock: fake.clock,
            memory: EventRangeMemory(),
            deviceZone: { Zones.chicago },
            locale: english
        )
        await running(model) {
            #expect(await eventually { isContent(model.state.agenda) })
        }
        #expect(model.today == day(2026, 11, 1))
        guard case .content(let rows) = model.state.agenda else { return }
        let ids = rows.map(\.id)
        #expect(ids.first == "celebration:usr_jordan_lee")
        #expect(ids.contains("event:evt_demo_allday"))
        #expect(ids.contains("event:evt_demo_overnight"))
        let overnight = rows.first { $0.id == "event:evt_demo_overnight" }
        #expect(overnight?.subtitle == "12:30 AM – 1:30 AM CST · North house")
    }
}
