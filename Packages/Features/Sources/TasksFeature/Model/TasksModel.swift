import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// What the Tasks tab draws.
struct TasksScreenState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case loading, error, empty, content }

    var segment: TasksSegment = .casework
    var window: TaskWindow = .dueSoon
    var assignedToMe = false
    var delays: DelayFilter = .show
    var query = ""
    var sections: [TaskSection] = []
    /// Matches on the server for this list and search, including pages not loaded yet.
    var totalCount = 0
    var counts: TaskCounts?
    var phase: Phase = .loading
    var isRefreshing = false
    var isLoadingMore = false
    var pageFailed = false
    /// A refresh failed while the last good list stays on screen.
    var refreshFailed = false
    var error: WaiveraError?
    var showsRequests = false
    /// Requests waiting on this person, for the count in the Requests segment.
    var waitingCount = 0

    var rowCount: Int { sections.reduce(0) { $0 + $1.rows.count } }

    /// False after a failed next page, until a refresh, so a bad page is not retried in a loop.
    var canLoadMore: Bool { phase == .content && rowCount < totalCount && !pageFailed }

    var segments: [TasksSegment] { showsRequests ? TasksSegment.allCases : [.casework, .myWork] }

    /// Delays are a client-task rule on the server and the web, so the chip is casework only.
    var showsDelays: Bool { segment == .casework }

    var searchPlaceholder: String {
        TasksStrings.text(segment == .myWork ? "tasks.search.mine" : "tasks.search.casework")
    }

    /// "12 open · 3 overdue · 2 delayed", or the match count while searching.
    var meta: String? {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty, phase != .loading {
            return TasksStrings.plural("tasks.meta.matches", totalCount)
        }
        guard let counts else { return nil }
        var parts = [TasksStrings.plural("tasks.meta.open", counts.open)]
        if counts.overdue > 0 { parts.append(TasksStrings.plural("tasks.meta.overdue", counts.overdue)) }
        if segment == .casework {
            if delays == .hide {
                parts.append(TasksStrings.text("tasks.meta.delaysHidden"))
            } else if counts.delayed > 0 {
                parts.append(TasksStrings.plural("tasks.meta.delayed", counts.delayed))
            }
        }
        return parts.joined(separator: " · ")
    }

    var emptyTitle: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return TasksStrings.text("tasks.empty.noMatch.title") }
        if segment == .casework, delays == .only { return TasksStrings.text("tasks.empty.delayed.title") }
        switch window {
        case .dueSoon: return TasksStrings.text("tasks.empty.dueSoon.title")
        case .overdue: return TasksStrings.text("tasks.empty.overdue.title")
        case .allOpen: return TasksStrings.text("tasks.empty.all.title")
        }
    }

    var emptyMessage: String {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            return TasksStrings.text("tasks.empty.noMatch.message")
        }
        if segment == .casework, delays == .only { return TasksStrings.text("tasks.empty.delayed.message") }
        switch window {
        case .dueSoon: return TasksStrings.text("tasks.empty.dueSoon.message")
        case .overdue: return TasksStrings.text("tasks.empty.overdue.message")
        case .allOpen:
            if segment == .myWork { return TasksStrings.text("tasks.empty.mine.message") }
            return TasksStrings.text(assignedToMe ? "tasks.empty.assigned.message" : "tasks.empty.casework.message")
        }
    }
}

/// The Tasks tab (Android `TasksViewModel`). Casework is the web's client task list, scoped by
/// the server to the person's role; My work is their own employee tasks. Changing the segment,
/// window, chip or search starts over at page one.
@MainActor
@Observable
final class TasksModel {
    static let searchDebounce: Duration = .milliseconds(300)

    private(set) var state = TasksScreenState()
    let feedback = TasksFeedback()

    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private let firstWeekday: Int
    @ObservationIgnored private let bag = TaskBag()
    @ObservationIgnored private var local = Local()
    @ObservationIgnored private var access = RequestAccess()
    @ObservationIgnored private var waiting: [ChangeRequest]?
    @ObservationIgnored private var started = false

    private struct Local: Equatable {
        var segment: TasksSegment = .casework
        var window: TaskWindow = .dueSoon
        var assignedToMe = false
        var delays: DelayFilter = .show
        var query = ""
        var items: [TaskSummary] = []
        var totalCount = 0
        var page = 1
        var counts: TaskCounts?
        var phase: TasksScreenState.Phase = .loading
        var isRefreshing = false
        var isLoadingMore = false
        var pageFailed = false
        var refreshFailed = false
        var error: WaiveraError?
        /// The list scope `items` belong to, so leaving Requests keeps a list that still fits.
        var loadedScope: TaskScope?

        /// Requests keeps the last task list's scope underneath it.
        var scope: TaskScope {
            switch segment {
            case .myWork: .mine
            case .requests: loadedScope ?? .casework
            case .casework: .casework
            }
        }

        var request: TaskQuery {
            TaskQuery(
                scope: scope,
                window: window,
                search: query.trimmingCharacters(in: .whitespacesAndNewlines),
                assignedToMe: assignedToMe && scope == .casework,
                delays: scope == .casework ? delays : .show
            )
        }
    }

    init(environment: DataEnvironment, firstWeekday: Int = Calendar.current.firstWeekday) {
        self.environment = environment
        self.firstWeekday = firstWeekday
        rebuild()
    }

    func run() async {
        if !started {
            started = true
            reload(showSkeleton: true)
        }
        await withDiscardingTaskGroup { group in
            group.addTask { await self.observeAccess() }
            group.addTask { await self.observeWaiting() }
        }
    }

    private func observeAccess() async {
        for await value in environment.requests.access() {
            access = value
            rebuild()
        }
    }

    private func observeWaiting() async {
        for await value in environment.requests.waiting() {
            waiting = value
            rebuild()
        }
    }

    func setSegment(_ segment: TasksSegment) {
        let current = local.segment
        guard segment != current else { return }
        local.segment = segment
        rebuild()
        let requests = environment.requests
        if segment == .requests {
            bag.run { try? await requests.refreshWaiting() }
        } else if current == .requests, local.scope == local.loadedScope {
            // Requests back to the same list keeps it.
        } else {
            reload(showSkeleton: true)
        }
    }

    func setWindow(_ window: TaskWindow) {
        guard window != local.window else { return }
        local.window = window
        reload(showSkeleton: true)
    }

    func setAssignedToMe(_ on: Bool) {
        guard on != local.assignedToMe else { return }
        local.assignedToMe = on
        reload(showSkeleton: true)
    }

    func setDelays(_ filter: DelayFilter) {
        guard filter != local.delays else { return }
        local.delays = filter
        reload(showSkeleton: true)
    }

    /// The list follows the search after a short pause, so each keystroke is not a request.
    func setQuery(_ query: String) {
        guard query != local.query else { return }
        local.query = query
        rebuild()
        bag.replace("search") { [weak self] in
            do {
                try await Task.sleep(for: Self.searchDebounce)
            } catch {
                return
            }
            self?.reload(showSkeleton: true)
        }
    }

    func refresh() async {
        // A pull also re-checks what the person may see, so a role change on the web shows here.
        let requests = environment.requests
        bag.run { try? await requests.refreshAccess() }
        await load(showSkeleton: false)
    }

    func retry() { reload(showSkeleton: true) }

    func loadMore() {
        guard !local.isLoadingMore, !local.pageFailed, local.phase == .content,
            local.items.count < local.totalCount
        else { return }
        local.isLoadingMore = true
        rebuild()
        let request = local.request
        let page = local.page + 1
        let tasks = environment.tasks
        bag.replace("page") { [weak self] in
            let result = await attempt { try await tasks.tasks(request, page: page) }
            guard let self, !Task.isCancelled else { return }
            self.local.isLoadingMore = false
            guard self.local.request == request else { return self.rebuild() }
            switch result {
            case .success(let next):
                let known = Set(self.local.items.map(\.id))
                self.local.items += next.items.filter { !known.contains($0.id) }
                self.local.totalCount = next.totalCount
                self.local.page = page
            case .failure:
                // A failed next page keeps what is shown; a refresh asks again.
                self.local.pageFailed = true
            }
            self.rebuild()
        }
    }

    // MARK: Private

    private func reload(showSkeleton: Bool) {
        bag.replace("list") { [weak self] in await self?.load(showSkeleton: showSkeleton) }
    }

    private func load(showSkeleton: Bool) async {
        let request = local.request
        if showSkeleton || local.phase == .error { local.phase = .loading }
        if showSkeleton {
            local.items = []
            local.counts = nil
        }
        local.isRefreshing = !showSkeleton
        local.isLoadingMore = false
        local.pageFailed = false
        local.refreshFailed = false
        local.loadedScope = request.scope
        rebuild()
        let tasks = environment.tasks
        let requests = environment.requests
        if !showSkeleton { bag.run { try? await requests.refreshWaiting() } }
        bag.replace("counts") { [weak self] in
            guard let counts = try? await tasks.counts(scope: request.scope, assignedToMe: request.assignedToMe),
                let self, !Task.isCancelled, self.local.request.scope == request.scope
            else { return }
            self.local.counts = counts
            self.rebuild()
        }
        let result = await attempt { try await tasks.tasks(request, page: 1) }
        guard !Task.isCancelled, local.request == request else { return }
        local.isRefreshing = false
        switch result {
        case .success(let page):
            local.items = page.items
            local.totalCount = page.totalCount
            local.page = 1
            local.phase = page.items.isEmpty ? .empty : .content
            local.error = nil
        case .failure(let error):
            let keeps = !local.items.isEmpty
            local.phase = keeps ? .content : .error
            local.refreshFailed = keeps
            local.error = WaiveraError.from(error)
            if keeps { feedback.show(TasksStrings.text("tasks.refreshFailed"), retry: .refresh) }
        }
        rebuild()
    }

    private func rebuild() {
        let zone = environment.calendar.scheduleTimeZone().zone
        let today = CalendarDate(environment.clock.now, in: zone)
        let me = environment.session.currentState.user?.id
        let rows = local.items.map { TasksRules.row($0, today: today, me: me, firstWeekday: firstWeekday) }
        var segment = local.segment
        if segment == .requests, access.loaded, !access.showsRequests { segment = .casework }
        var next = TasksScreenState()
        next.segment = segment
        next.window = local.window
        next.assignedToMe = local.assignedToMe
        next.delays = local.delays
        next.query = local.query
        next.sections = TasksRules.sections(rows)
        next.totalCount = local.totalCount
        next.counts = local.counts
        next.phase = local.phase
        next.isRefreshing = local.isRefreshing
        next.isLoadingMore = local.isLoadingMore
        next.pageFailed = local.pageFailed
        next.refreshFailed = local.refreshFailed
        next.error = local.error
        next.showsRequests = access.showsRequests
        next.waitingCount = access.showsRequests ? (waiting ?? []).filter { $0.kind.reviewableHere }.count : 0
        if next != state { state = next }
    }
}

/// `Result(catching:)` for async work, run in the caller's isolation.
func attempt<Value>(
    isolation: isolated (any Actor)? = #isolation,
    _ body: () async throws -> Value
) async -> Result<Value, any Error> {
    do {
        return .success(try await body())
    } catch {
        return .failure(error)
    }
}
