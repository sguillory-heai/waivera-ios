import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// What the inbox draws.
struct NoticesScreenState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case loading, error, empty, content }

    var filter: NoticeFilter = .all
    var groups: [NoticeGroup] = []
    /// The server's unread count, so it includes notifications older than the first page.
    var unreadCount = 0
    var phase: Phase = .loading
    var error: WaiveraError?
    /// A refresh failed while the last good list stays on screen.
    var refreshFailed = false
    var isMarkingAllRead = false
    var isOffline = false
    /// Notifications loaded before the chip narrows them.
    var totalCount = 0

    /// Notifications exist, but none of them in the chosen chip.
    var isFilteredEmpty: Bool { phase == .empty && totalCount > 0 }
}

/// The notifications inbox, the same list as the web bell (Android `NoticesViewModel`). It
/// refreshes on open; the realtime sync refetches on new rows and after a reconnect.
@MainActor
@Observable
final class NoticesModel {
    private(set) var state = NoticesScreenState()
    let feedback = TodayFeedback()

    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private let clock: any WaiveraClock
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private let tasks = TaskBag()
    @ObservationIgnored private var resource = Resource<NoticeFeed>()
    @ObservationIgnored private var filter: NoticeFilter = .all
    @ObservationIgnored private var isMarkingAllRead = false
    @ObservationIgnored private var connection: ConnectionBanner = .hidden
    @ObservationIgnored private var now: Date
    @ObservationIgnored private var navigation = NavigationGuard()

    init(
        environment: DataEnvironment,
        clock: any WaiveraClock,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.environment = environment
        self.clock = clock
        self.uptime = uptime
        now = clock.now
        rebuild()
    }

    func run() async {
        let notices = environment.notices
        await withDiscardingTaskGroup { group in
            group.addTask { await self.observe() }
            group.addTask { await self.observeConnection() }
            group.addTask { await self.tick() }
            group.addTask { await notices.refresh() }
        }
    }

    func refresh() async { await environment.notices.refresh() }

    func setFilter(_ filter: NoticeFilter) {
        self.filter = filter
        rebuild()
    }

    /// Where the row goes; it is marked read at once unless nothing can open it, so its
    /// reminder is not lost. `nil` for a second tap within 600 ms or a row that left the list.
    func open(_ id: String) -> NoticeDestination? {
        guard navigation.allows(at: uptime()) else { return nil }
        guard let notice = resource.value?.items.first(where: { $0.id == id }) else { return nil }
        let destination = NoticeLinks(webBase: environment.webBaseURL).destination(notice)
        guard destination != .none else {
            feedback.show(.nothingToOpen)
            return nil
        }
        if !notice.isRead {
            let notices = environment.notices
            tasks.run { try? await notices.markRead(id: id) }
        }
        return destination
    }

    func markAllRead() {
        guard !isMarkingAllRead else { return }
        isMarkingAllRead = true
        rebuild()
        let notices = environment.notices
        tasks.run { [weak self] in
            do {
                try await notices.markAllRead()
                self?.finishMarkAll(failed: false)
            } catch {
                self?.finishMarkAll(failed: true)
            }
        }
    }

    func retry(_ toast: TodayToast) {
        feedback.dismiss(toast.id)
        switch toast.notice {
        case .markAllFailed: markAllRead()
        case .nothingToOpen: break
        default: tasks.run { [weak self] in await self?.refresh() }
        }
    }

    // MARK: Private

    private func finishMarkAll(failed: Bool) {
        isMarkingAllRead = false
        rebuild()
        if failed { feedback.fail(.markAllFailed) }
    }

    private func observe() async {
        for await value in environment.notices.feed() {
            resource = value
            rebuild()
        }
    }

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

    private func rebuild() {
        let zone = environment.calendar.scheduleTimeZone().zone
        let items = resource.value?.items ?? []
        let groups = NoticeRules.groups(
            items,
            filter: filter,
            links: NoticeLinks(webBase: environment.webBaseURL),
            now: now,
            zone: zone
        )
        var next = NoticesScreenState()
        next.filter = filter
        next.groups = groups
        next.unreadCount = resource.value?.unreadCount ?? 0
        next.totalCount = items.count
        next.error = resource.error
        next.phase =
            if !groups.isEmpty { .content } else if resource.updatedAt != nil || !items.isEmpty {
                .empty
            } else if resource.error != nil { .error } else { .loading }
        next.refreshFailed = resource.error != nil && next.phase != .error
        next.isMarkingAllRead = isMarkingAllRead
        next.isOffline = connection == .offline
        if next != state { state = next }
    }
}
