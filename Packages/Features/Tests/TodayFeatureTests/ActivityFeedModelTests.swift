import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TodayFeature

/// The full Activity screen: loading, empty, error, reconnect, search, open and mark read.
@MainActor
struct ActivityFeedModelTests {
    private func running(_ model: ActivityFeedModel, _ body: () async throws -> Void) async rethrows {
        let task = Task { await model.run() }
        defer { task.cancel() }
        try await body()
    }

    @Test func loadingThenTheFeedRendersNewestFirst() async {
        let harness = TodayHarness(.slow)
        let model = harness.activityModel()
        await running(model) {
            #expect(model.state.isInitialLoad)
            #expect(
                await eventually {
                    harness.clock.advance(by: 0.2)
                    return !model.state.isInitialLoad
                }
            )
            #expect(!model.state.section.rows.isEmpty)
            #expect(model.state.loadError == nil)
        }
    }

    @Test func emptyAFeedWithNothingInItSaysSo() async {
        let model = TodayHarness(.empty).activityModel()
        await running(model) {
            #expect(await eventually { model.state.section.isEmpty })
            #expect(!model.state.isInitialLoad)
            #expect(!model.state.section.isFilteredEmpty)
        }
    }

    @Test func errorNothingCachedShowsTheErrorStateAndTryAgainReloads() async {
        let harness = TodayHarness(.failing)
        let model = harness.activityModel()
        await running(model) {
            #expect(await eventually { model.state.loadError == .server(statusCode: 503) })
            harness.fakes.setControls(FakeControls())
            model.retry(TodayToast(.refreshFailed))
            #expect(await eventually { model.state.loadError == nil && !model.state.section.rows.isEmpty })
        }
    }

    @Test func reconnectClearsTheOfflineLineAndLeavesTheResyncToTheDataLayer() async {
        let harness = TodayHarness()
        let model = harness.activityModel()
        await running(model) {
            #expect(await eventually { model.state.section.isReady })
            harness.fakes.realtimeStatus.setOffline(true)
            #expect(await eventually { model.state.quietStatus != nil })
            let refreshes = harness.fakes.activity.resource.refreshCount
            harness.fakes.realtimeStatus.setOffline(false)
            #expect(await eventually { model.state.quietStatus == nil })
            await settle()
            #expect(harness.fakes.activity.resource.refreshCount == refreshes)
        }
    }

    @Test func searchFiltersByShownTextAndActorAndClearFiltersResetsEverything() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = FakeActivityRepository(
            [
                Fixture.activity(1, .threadReply, summary: "I'll bring the forms.", actor: "Sam Ortiz"),
                Fixture.activity(2, .reaction, at: "2026-11-01T15:00:00Z", actor: "Dana Kim", emoji: "🎉"),
                Fixture.activity(
                    3,
                    .mention,
                    at: "2026-11-01T14:00:00Z",
                    summary: "Jordan mentioned you",
                    actor: "Jordan"
                ),
            ],
            clock: clock
        )
        let model = TodayHarness(clock: clock, activity: repository).activityModel()
        await running(model) {
            #expect(await eventually { model.state.section.rows.count == 3 })
            model.setQuery("dana")
            #expect(model.state.section.rows.map(\.id) == [2])
            model.setQuery("FORMS")
            #expect(model.state.section.rows.map(\.id) == [1])
            model.setFilter(.mentions)
            #expect(model.state.section.isFilteredEmpty)
            model.clearFilters()
            #expect(model.state.section.rows.count == 3)
            #expect(model.state.section.query.isEmpty)
            #expect(!model.state.section.isFiltered)
        }
    }

    @Test func openingARowMarksItReadAndOpensItsThreadByRoot() async throws {
        let clock = ManualClock(now: Fixture.now)
        let reply = Fixture.activity(1, conversation: 40, message: 9_334, threadRoot: 9_330)
        let repository = FakeActivityRepository([reply], clock: clock)
        let harness = TodayHarness(clock: clock, activity: repository)
        let model = harness.activityModel()
        try await running(model) {
            #expect(await eventually { model.state.section.unreadCount == 1 })
            let row = try #require(model.state.section.rows.first)
            #expect(model.open(row) == .thread(rootMessageId: 9_330, conversationId: 40, targetMessageId: 9_334))
            #expect(model.state.section.unreadCount == 0)
            #expect(model.open(row) == nil, "a double tap opens one screen")
            #expect(await eventually { repository.calls.all == ["markRead:1"] })
        }
    }

    @Test func markAllReadConfirmsWithAHapticAndAFailureSaysSo() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = FakeActivityRepository([Fixture.activity(1), Fixture.activity(2)], clock: clock)
        let model = TodayHarness(clock: clock, activity: repository).activityModel()
        await running(model) {
            #expect(await eventually { model.state.section.unreadCount == 2 })
            repository.actionFailure.update { $0 = .offline }
            model.markAllRead()
            #expect(await eventually { model.feedback.toast?.notice == .markAllFailed })
            #expect(await eventually { model.state.section.unreadCount == 2 })
            repository.actionFailure.update { $0 = nil }
            model.markAllRead()
            #expect(await eventually { model.feedback.successCount == 1 && model.state.section.unreadCount == 0 })
        }
    }

    @Test func aMentionIsListedHereEvenThoughTodayPinsIt() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = FakeActivityRepository([Fixture.activity(1, .mention)], clock: clock)
        let model = TodayHarness(clock: clock, activity: repository).activityModel()
        await running(model) {
            #expect(await eventually { model.state.section.rows.map(\.id) == [1] })
        }
    }
}
