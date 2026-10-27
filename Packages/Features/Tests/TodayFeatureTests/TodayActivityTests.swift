import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TodayFeature

/// Today's activity section against fake feeds: optimistic reads, filters, realtime inserts and
/// paging up to the automatic cap.
@MainActor
struct TodayActivityTests {
    private func running(_ model: TodayModel, _ body: () async throws -> Void) async rethrows {
        let task = Task { await model.run() }
        defer { task.cancel() }
        try await body()
    }

    // MARK: Activity

    @Test func markReadTappingAnUnreadRowMarksItReadAndDropsTheCount() async throws {
        let clock = ManualClock(now: Fixture.now)
        let items = [Fixture.activity(1), Fixture.activity(2, at: "2026-11-01T15:00:00Z")]
        let repository = FakeActivityRepository(items, clock: clock)
        let harness = TodayHarness(clock: clock, activity: repository)
        let model = harness.todayModel()
        try await running(model) {
            #expect(await eventually { model.state.activity.unreadCount == 2 })
            let row = try #require(model.state.activity.rows.first)
            let destination = model.navigate(to: .chat(row.destination), markingRead: row.id)
            #expect(destination == .chat(row.destination))
            #expect(model.state.activity.rows.first?.isRead == true, "optimistic")
            #expect(model.state.activity.unreadCount == 1)
            #expect(await eventually { repository.calls.all == ["markRead:1"] })
            await settle()
            #expect(model.state.activity.rows.first?.isRead == true)
        }
    }

    @Test func markReadAFailureReturnsTheRowToUnreadWithRetry() async throws {
        let clock = ManualClock(now: Fixture.now)
        let repository = FakeActivityRepository([Fixture.activity(1)], clock: clock)
        repository.actionFailure.update { $0 = .offline }
        let harness = TodayHarness(clock: clock, activity: repository)
        let model = harness.todayModel()
        try await running(model) {
            #expect(await eventually { model.state.activity.unreadCount == 1 })
            model.markRead(1)
            #expect(model.state.activity.unreadCount == 0)
            #expect(await eventually { model.feedback.toast?.notice == .markReadFailed(activityId: 1) })
            #expect(await eventually { model.state.activity.rows.first?.isRead == false })
            #expect(model.state.activity.unreadCount == 1)
            #expect(model.feedback.failureCount == 1)

            repository.actionFailure.update { $0 = nil }
            let toast = try #require(model.feedback.toast)
            model.retry(toast)
            #expect(model.feedback.toast == nil)
            #expect(
                await eventually { model.state.activity.unreadCount == 0 && repository.calls.count("markRead") == 2 }
            )
        }
    }

    @Test func markAllEveryLoadedActivityBecomesReadAndAFailureRestoresThem() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = FakeActivityRepository(
            [Fixture.activity(1), Fixture.activity(2, .reaction), Fixture.activity(3, .mention)],
            clock: clock
        )
        repository.actionFailure.update { $0 = .server(statusCode: 500) }
        let harness = TodayHarness(clock: clock, activity: repository)
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.unreadCount == 3 })
            #expect(model.state.needsYou.items.contains { $0.id == "mention-3" })
            model.markAllRead()
            #expect(model.state.activity.unreadCount == 0, "optimistic")
            #expect(model.state.activity.isMarkingAllRead)
            #expect(await eventually { model.feedback.toast?.notice == .markAllFailed })
            #expect(
                await eventually { model.state.activity.unreadCount == 3 && !model.state.activity.isMarkingAllRead }
            )

            repository.actionFailure.update { $0 = nil }
            model.markAllRead()
            #expect(await eventually { model.feedback.successCount == 1 })
            #expect(
                await eventually { model.state.activity.unreadCount == 0 && !model.state.activity.isMarkingAllRead }
            )
            #expect(!model.state.needsYou.items.contains { $0.id == "mention-3" })
        }
    }

    @Test func filtersUnreadOnlyEmptiesWhenTheLastUnreadItemIsOpened() async throws {
        let clock = ManualClock(now: Fixture.now)
        let repository = FakeActivityRepository([Fixture.activity(1), Fixture.activity(2, isRead: true)], clock: clock)
        let harness = TodayHarness(clock: clock, activity: repository)
        let model = harness.todayModel()
        try await running(model) {
            #expect(await eventually { model.state.activity.isReady })
            model.toggleUnreadOnly()
            #expect(model.state.activity.rows.map(\.id) == [1])
            let row = try #require(model.state.activity.rows.first)
            _ = model.navigate(to: .chat(row.destination), markingRead: row.id)
            #expect(model.state.activity.isFilteredEmpty)
            #expect(!model.state.activity.isEmpty)
            model.setFilter(.reactions)
            model.toggleUnreadOnly()
            #expect(model.state.activity.isFilteredEmpty, "no reactions at all")
            model.setFilter(.all)
            #expect(model.state.activity.rows.count == 2)
        }
    }

    @Test func realtimeANewActivityAppearsAtTheTopWithoutARefetch() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = FakeActivityRepository([Fixture.activity(1)], clock: clock)
        let harness = TodayHarness(clock: clock, activity: repository)
        let model = harness.todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.rows.count == 1 })
            let refreshes = repository.resource.refreshCount
            repository.resource.mutate { feed in
                feed.items.insert(Fixture.activity(9, .reaction, at: "2026-11-01T16:29:00Z"), at: 0)
            }
            #expect(await eventually { model.state.activity.rows.first?.id == 9 })
            #expect(model.state.activity.unreadCount == 2)
            #expect(repository.resource.refreshCount == refreshes)
        }
    }

    // MARK: Paging

    @Test func pagingAFullPageWithUnreadAtItsEndLoadsTheNextPage() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = PagedActivityRepository(
            pages: [PagedActivityRepository.page(1), PagedActivityRepository.page(2, count: 10)],
            clock: clock
        )
        let model = TodayHarness(clock: clock, activity: repository).todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.totalCount == 40 })
            await settle()
            #expect(repository.calls.count("loadMore") == 1)
            #expect(model.state.activity.unreadCount == 40)
            #expect(!model.state.activity.unreadIsLowerBound)
            #expect(!model.state.activity.hasMore)
        }
    }

    @Test func pagingAShortPageMakesNoFurtherRequest() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = PagedActivityRepository(pages: [PagedActivityRepository.page(1, count: 12)], clock: clock)
        let model = TodayHarness(clock: clock, activity: repository).todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.totalCount == 12 })
            model.loadMoreActivity()
            await settle()
            #expect(repository.calls.count("loadMore") == 0)
        }
    }

    @Test func pagingStopsAtTheCapAndShowsTheCountAsALowerBound() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = PagedActivityRepository(pages: [PagedActivityRepository.page(1)], endless: true, clock: clock)
        let model = TodayHarness(clock: clock, activity: repository).todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.unreadIsLowerBound })
            await settle()
            #expect(repository.calls.count("loadMore") == ActivityController.maxAutoPages)
            #expect(model.state.activity.unreadCount == 30 * (ActivityController.maxAutoPages + 1))
            #expect(model.state.activity.hasMore)
            // Scrolling still loads more by hand.
            model.loadMoreActivity()
            #expect(await eventually { repository.calls.count("loadMore") == ActivityController.maxAutoPages + 1 })
        }
    }

    @Test func pagingAFailedPageShowsRetryAndRetryLoadsIt() async {
        let clock = ManualClock(now: Fixture.now)
        let repository = PagedActivityRepository(
            pages: [PagedActivityRepository.page(1, isRead: true), PagedActivityRepository.page(2, count: 5)],
            clock: clock
        )
        repository.setLoadMoreFailure(.offline)
        let model = TodayHarness(clock: clock, activity: repository).todayModel()
        await running(model) {
            #expect(await eventually { model.state.activity.hasMore })
            model.loadMoreActivity()
            #expect(await eventually { model.state.activity.loadMoreFailed })
            model.loadMoreActivity()
            await settle()
            #expect(repository.calls.count("loadMore") == 1, "no automatic retry loop")
            // A failed page leaves the feed failed, so Retry reloads page 1 and paging starts again.
            repository.setLoadMoreFailure(nil)
            model.retryMoreActivity()
            #expect(await eventually { repository.calls.count("refresh") == 2 && !model.state.activity.loadMoreFailed })
            model.loadMoreActivity()
            #expect(await eventually { model.state.activity.totalCount == 35 })
            #expect(!model.state.activity.hasMore)
        }
    }
}
