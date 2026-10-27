import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// What the full Activity screen draws.
struct ActivityScreenState: Equatable, Sendable {
    var section = ActivitySection()
    /// Nothing cached and the first load still running.
    var isInitialLoad = true
    /// Nothing cached and the load failed: the full error state with Try again.
    var loadError: WaiveraError?
    var quietStatus: QuietStatus?
    var isRefreshing = false
}

/// The full activity feed (06 §A): search, chips, paging, mark read and mark all read. Rows
/// open their message, or their thread by root id.
@MainActor
@Observable
final class ActivityFeedModel {
    private(set) var state = ActivityScreenState()
    let feedback = TodayFeedback()

    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private let clock: any WaiveraClock
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private let tasks = TaskBag()
    @ObservationIgnored private let activity: ActivityController
    @ObservationIgnored private var now: Date
    @ObservationIgnored private var connection: ConnectionBanner = .hidden
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var navigation = NavigationGuard()
    @ObservationIgnored private var wasFailing = false

    init(
        environment: DataEnvironment,
        clock: any WaiveraClock,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.environment = environment
        self.clock = clock
        self.uptime = uptime
        now = clock.now
        activity = ActivityController(repository: environment.activity, feedback: feedback, tasks: tasks)
        activity.onChange = { [weak self] in self?.rebuild() }
        rebuild()
    }

    func run() async {
        now = clock.now
        await withDiscardingTaskGroup { group in
            group.addTask { await self.activity.observe() }
            group.addTask { await self.observeConnection() }
            group.addTask { await self.tick() }
            group.addTask { await self.refreshIfStale() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        rebuild()
        await activity.refresh()
        isRefreshing = false
        rebuild()
    }

    func setFilter(_ filter: ActivityFilter) { activity.setFilter(filter) }
    func toggleUnreadOnly() { activity.toggleUnreadOnly() }
    func setQuery(_ query: String) { activity.setQuery(query) }
    func clearFilters() { activity.clearFilters() }
    func markRead(_ activityId: Int64) { activity.markRead(activityId) }
    func markAllRead() { activity.markAllRead() }
    func loadMore() { activity.loadMoreIfPossible() }
    func retryMore() { activity.retryMore() }

    func retry(_ toast: TodayToast) {
        feedback.dismiss(toast.id)
        switch toast.notice {
        case .refreshFailed: tasks.run { [weak self] in await self?.refresh() }
        case .markReadFailed(let id): activity.markRead(id)
        case .markAllFailed: activity.markAllRead()
        case .invitationAnswered, .invitationFailed: break
        }
    }

    /// Opening a row marks it read (optimistically) and follows it; a second tap within 600 ms is dropped.
    func open(_ row: ActivityRow) -> ChatDestination? {
        guard navigation.allows(at: uptime()) else { return nil }
        activity.markRead(row.id)
        return row.destination
    }

    // MARK: Private

    /// Only for the offline line: the data layer refetches the feed itself after a reconnect.
    private func observeConnection() async {
        for await banner in environment.realtimeStatus.banner() {
            connection = banner
            rebuild()
        }
    }

    private func tick() async {
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: TodayModel.tickInterval)
            } catch {
                return
            }
            now = clock.now
            rebuild()
        }
    }

    private func refreshIfStale() async {
        let current = await latest(environment.activity.feed())
        guard let updatedAt = current?.updatedAt, clock.now.timeIntervalSince(updatedAt) < TodayModel.activityFreshFor
        else {
            await activity.refresh()
            return
        }
    }

    private func rebuild() {
        let zone = environment.calendar.scheduleTimeZone().zone
        let resource = activity.resource
        let section = ActivityAssembler.section(resource, local: activity.local, now: now, zone: zone)
        let status = SourceStatus(resource) { !$0.items.isEmpty }
        var next = ActivityScreenState()
        next.section = section
        next.isInitialLoad = status.isLoading
        next.loadError = status.failed ? status.error : nil
        next.isRefreshing = isRefreshing
        if connection == .offline {
            next.quietStatus = .offline(since: resource.updatedAt.map { TimeLabels.past($0, now: now, zone: zone) })
        }
        if next != state { state = next }
        let failing = resource.error != nil && status.hasContent
        if failing, !wasFailing, connection != .offline { feedback.show(.refreshFailed) }
        wasFailing = failing
    }
}
