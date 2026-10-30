import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TodayFeature

/// The Today model against the fake data layer: loading, empty, error, reconnect, optimistic
/// writes and the clock. Time only moves when a test advances the `ManualClock`.
@MainActor
struct TodayModelTests {
    /// Runs the model like the screen's `.task` does, for the length of `body`.
    private func running(_ model: TodayModel, _ body: () async throws -> Void) async rethrows {
        let task = Task { await model.run() }
        defer { task.cancel() }
        try await body()
    }

    // MARK: Loading, empty, error

    @Test func loadingNothingCachedShowsTheInitialLoad() async {
        let harness = TodayHarness(.slow)
        let model = harness.todayModel()
        await running(model) {
            #expect(model.state.isInitialLoad)
            #expect(await eventually { harness.clock.pendingSleepers >= 4 })
            #expect(model.state.isInitialLoad, "nothing renders until a source answers")
            #expect(
                await eventually {
                    harness.clock.advance(by: 0.2)
                    return !model.state.isInitialLoad
                }
            )
            #expect(model.state.loadError == nil)
        }
    }

    @Test func emptyEverythingSyncedAndNothingPendingIsAllCaughtUp() async {
        let harness = TodayHarness(.empty)
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.isAllCaughtUp })
            #expect(model.state.needsYou.items.isEmpty)
            #expect(model.state.nextUp.isReady)
            #expect(model.state.nextUp.items.isEmpty)
            #expect(model.state.activity.isEmpty)
        }
    }

    @Test func errorNothingCachedAndEverySourceFailedShowsTheErrorState() async {
        let harness = TodayHarness(.failing)
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.loadError != nil })
            #expect(model.state.loadError == .server(statusCode: 503))
            #expect(!model.state.isInitialLoad)
            #expect(!model.state.isAllCaughtUp)
            #expect(model.feedback.toast == nil, "the full error state is not repeated as a toast")
        }
    }

    @Test func errorAFailedRefreshKeepsCachedContentAndSaysSoOnce() async {
        let harness = TodayHarness()
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { !model.state.needsYou.items.isEmpty && model.state.activity.isReady })
            let shown = model.state.needsYou.items
            harness.fakes.setControls(FakeControls(failure: .server(statusCode: 500)))
            await model.refresh()
            #expect(model.feedback.toast?.notice == .refreshFailed)
            #expect(model.feedback.toast?.notice.offersRetry == true)
            #expect(model.state.needsYou.items == shown)
            #expect(model.state.loadError == nil)
            #expect(!model.state.isRefreshing)
        }
    }

    @Test func refreshRefreshesEverySourceIncludingBothWeeksInTheSavedZone() async {
        let harness = TodayHarness()
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.isReady && model.state.nextUp.isReady })
            let before = harness.fakes.activity.resource.refreshCount
            let weeks = harness.calendar.calls.count("refresh:week")
            let milestones = harness.calendar.milestoneResource.refreshCount
            await model.refresh()
            #expect(harness.fakes.activity.resource.refreshCount == before + 1)
            #expect(harness.calendar.calls.count("refresh:week") == weeks + 2)
            #expect(harness.calendar.milestoneResource.refreshCount == milestones + 1)
            #expect(harness.calendar.calls.all.contains("refresh:week:2026-11-01"))
            #expect(harness.calendar.calls.all.contains("refresh:week:2026-11-08"))
        }
    }

    @Test func openStaleSourcesRefreshOnOpenAndFreshOnesDoNot() async {
        let harness = TodayHarness()
        let first = harness.todayModel()
        await running(first) {
            #expect(await eventually { harness.fakes.activity.resource.refreshCount == 1 })
        }
        let fresh = harness.todayModel()
        await running(fresh) {
            #expect(await eventually { fresh.state.activity.isReady })
            await settle()
            #expect(harness.fakes.activity.resource.refreshCount == 1, "fresh for 30 s")
        }
        harness.clock.advance(by: TodayModel.activityFreshFor + 1)
        let stale = harness.todayModel()
        await running(stale) {
            #expect(await eventually { harness.fakes.activity.resource.refreshCount == 2 })
        }
    }

    // MARK: Reconnect and offline

    @Test func reconnectOfflineShowsTheQuietLineAndLeavesTheResyncToTheDataLayer() async {
        let harness = TodayHarness()
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.isReady && model.state.nextUp.isReady })
            harness.fakes.realtimeStatus.setOffline(true)
            #expect(
                await eventually {
                    if case .offline = model.state.quietStatus { return true }
                    return false
                }
            )
            let feeds = harness.fakes.activity.resource.refreshCount
            let weeks = harness.calendar.calls.count("refresh:week")
            harness.fakes.realtimeStatus.setOffline(false)
            #expect(await eventually { model.state.quietStatus == nil })
            await settle()
            #expect(harness.fakes.activity.resource.refreshCount == feeds, "the data layer resyncs activity itself")
            #expect(harness.calendar.calls.count("refresh:week") == weeks, "the data layer resyncs the calendar")
        }
    }

    @Test func offlineFailuresDoNotAlsoRaiseARefreshToast() async {
        let harness = TodayHarness()
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.isReady })
            harness.fakes.realtimeStatus.setOffline(true)
            #expect(await eventually { model.state.quietStatus != nil })
            harness.fakes.setControls(FakeControls(failure: .offline))
            await model.refresh()
            #expect(model.feedback.toast == nil)
        }
    }

    // MARK: Invitations

    @Test func invitationAnsweringHidesItAtOnceAndAFailureBringsItBack() async throws {
        let invite = Fixture.event("evt_review", "2026-11-02T15:00:00Z", "2026-11-02T16:00:00Z", response: .pending)
        let harness = TodayHarness(events: [invite])
        let model = harness.todayModel()
        try await running(model) {
            #expect(await eventually { model.state.needsYou.items.contains { $0.id == "invite-evt_review" } })
            harness.calendar.controls.update { $0 = FakeControls(failure: .offline) }
            model.respond(toEventId: "evt_review", accept: true)
            #expect(!model.state.needsYou.items.contains { $0.id == "invite-evt_review" }, "optimistic")
            #expect(
                await eventually {
                    model.feedback.toast?.notice == .invitationFailed(eventId: "evt_review", accept: true)
                }
            )
            #expect(model.state.needsYou.items.contains { $0.id == "invite-evt_review" })

            harness.calendar.controls.update { $0 = FakeControls() }
            let toast = try #require(model.feedback.toast)
            model.retry(toast)
            #expect(await eventually { model.feedback.toast?.notice == .invitationAnswered(accept: true) })
            #expect(harness.calendar.calls.count("respond:evt_review:true") == 2)
            #expect(!model.state.needsYou.items.contains { $0.id == "invite-evt_review" })
        }
    }

    @Test func invitationASuccessfulAnswerConfirmsAndTheEventJoinsNextUp() async {
        let invite = Fixture.event("evt_review", "2026-11-01T17:00:00Z", "2026-11-01T18:00:00Z", response: .pending)
        let harness = TodayHarness(events: [invite])
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { !model.state.needsYou.items.isEmpty })
            #expect(model.state.nextUp.items.isEmpty, "pending items stay under Needs you")
            model.respond(toEventId: "evt_review", accept: true)
            #expect(await eventually { model.feedback.successCount == 1 })
            #expect(model.feedback.toast?.notice == .invitationAnswered(accept: true))
            #expect(await eventually { model.state.nextUp.items.map(\.eventId) == ["evt_review"] })
        }
    }

    // MARK: Time

    @Test func timeRelativeLabelsTickWithTheClock() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = FakeActivityRepository([Fixture.activity(1, at: "2026-11-01T16:25:00Z")], clock: clock)
        let harness = TodayHarness(clock: clock, activity: repository)
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.rows.first?.when == .minutesAgo(5) })
            #expect(await eventually { harness.clock.pendingSleepers >= 1 })
            harness.clock.advance(by: 60)
            #expect(await eventually { model.state.activity.rows.first?.when == .minutesAgo(6) })
        }
    }

    @Test func timeTheScheduleWeeksStartOnTheEmployeesDateNotUTC() async {
        // 03:00 UTC on 1 Nov is still 31 Oct in Chicago.
        let harness = TodayHarness(clock: ManualClock(now: Fixture.instant("2026-11-01T03:00:00Z")))
        let model = harness.todayModel()
        await running(model) {
            #expect(
                await eventually {
                    harness.calendar.calls.all.contains("refresh:week:2026-10-31")
                        && harness.calendar.calls.all.contains("refresh:week:2026-11-07")
                }
            )
            #expect(!harness.calendar.calls.all.contains("refresh:week:2026-11-01"))
            #expect(model.state.date == Fixture.date(2026, 10, 31))
        }
    }

    @Test func timeMidnightInTheSavedZoneMovesTheObservedWeeks() async {
        // 23:59:45 CDT on 31 Oct; the next tick lands after midnight.
        let harness = TodayHarness(clock: ManualClock(now: Fixture.instant("2026-11-01T04:59:45Z")))
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { harness.calendar.calls.all.contains("refresh:week:2026-10-31") })
            #expect(await eventually { harness.clock.pendingSleepers >= 1 })
            harness.clock.advance(by: 30)
            #expect(await eventually { harness.calendar.calls.all.contains("refresh:week:2026-11-01") })
            #expect(model.state.date == Fixture.date(2026, 11, 1))
        }
    }

    // MARK: Navigation

    @Test func navigationADoubleTapOpensOneScreen() async {
        let harness = TodayHarness()
        let model = harness.todayModel()
        #expect(model.navigate(to: .schedule) == .schedule)
        #expect(model.navigate(to: .activity) == nil)
        harness.uptime.advance(by: NavigationGuard.interval + 0.01)
        #expect(model.navigate(to: .event(id: "evt_1")) == .event(id: "evt_1"))
    }

    @Test func needsYouExpandsAndCollapses() async {
        let conversations = (1...7).map { Fixture.direct($0) }
        let harness = TodayHarness(conversations: conversations)
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.needsYou.hiddenCount == 4 })
            model.toggleNeedsYouExpanded()
            #expect(model.state.needsYou.items.count == 7)
            model.toggleNeedsYouExpanded()
            #expect(model.state.needsYou.items.count == 3)
        }
    }

    // MARK: Hero

    @Test func theHeroGreetsTheSignedInPersonAndCountsAnAnsweredInvitationAsHandled() async {
        let invite = Fixture.event("invite", "2026-11-02T15:00:00Z", "2026-11-02T16:00:00Z", response: .pending)
        let harness = TodayHarness(.empty, events: [invite])
        await harness.fakes.session.start()
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.handledObservation != nil })
            #expect(
                model.state.greeting?.firstName
                    == GreetingRules.firstName(
                        harness.fakes.data.user.firstName,
                        displayName: harness.fakes.data.user.displayName
                    )
            )
            #expect(model.state.progress == TodayProgress(handled: 0, open: 1))
            #expect(model.state.needsYou.kinds == [.invitation: 1])
            #expect(!model.state.isAllCaughtUp)
            model.respond(toEventId: "invite", accept: true)
            #expect(model.state.progress == TodayProgress(handled: 1, open: 0))
            #expect(model.state.isAllCaughtUp, "nine of nine: the reward hero")
            #expect(harness.handledStore.load()?.handled == 1, "the tally is saved for the next launch")
        }
        let relaunched = harness.todayModel()
        await running(relaunched) {
            #expect(await eventually { relaunched.state.progress?.handled == 1 })
        }
    }

    @Test func loadingTheHeroWaitsForNeedsYouAndTheStatsShowDashes() async {
        let harness = TodayHarness(.slow)
        let model = harness.todayModel()
        await running(model) {
            #expect(model.state.progress == nil)
            #expect(model.state.stats == TodayStats())
            #expect(model.state.day == nil)
        }
    }
}
