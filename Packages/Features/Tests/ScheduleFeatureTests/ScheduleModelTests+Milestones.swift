import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ScheduleFeature

/// Milestones, pull to refresh and the demo environment.
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
        let rig = harness(feed: CalendarFeed(events: [event("e1", "2026-10-27T16:00:00Z", "2026-10-27T17:00:00Z")]))
        rig.calendar.milestoneFailure.update { $0 = .server(statusCode: 500) }
        await running(rig.model) {
            #expect(await eventually { isContent(rig.model.state.agenda) })
            #expect(await eventually { rig.model.state.milestonesFailed })
        }
    }

    @Test func milestonesAppearOnTheGridAndInTheAgenda() async {
        let rig = harness(milestones: [
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
        await running(rig.model) {
            #expect(await eventually { isContent(rig.model.state.agenda) })
        }
        #expect(rig.model.state.cells.first { $0.date == day(2026, 10, 30) }?.marker.celebrations == 1)
        guard case .content(let rows) = rig.model.state.agenda else { return }
        #expect(rows.first?.title == "It's Jordan Lee's birthday today!")
        #expect(rows.first?.accessibilityLabel == "Jordan Lee is celebrating a birthday today.")
    }

    @Test func pullToRefreshRefreshesFeedAndMilestonesTogether() async {
        let rig = harness()
        await rig.model.refresh()
        #expect(rig.calendar.calls.count("refresh:month") == 1)
        #expect(rig.calendar.calls.count("milestones") == 1)
    }

    @Test func freshFeedIsNotRefetchedOnAppearance() async {
        let rig = harness()
        let fresh = Resource(value: CalendarFeed(), phase: .loaded, updatedAt: rig.clock.now)
        rig.calendar.cell(.month, day(2026, 10, 27)).set(fresh)
        await running(rig.model) {
            #expect(await eventually { rig.model.state.agenda == .empty })
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(rig.calendar.calls.count("refresh:") == 0)
    }

    @Test func demoEnvironmentRendersTodaysAgendaOnTheFallBackDay() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        await fake.environment.launch()
        let model = ScheduleModel(
            calendar: fake.calendar,
            session: fake.session,
            realtime: fake.realtimeStatus,
            clock: fake.clock,
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
