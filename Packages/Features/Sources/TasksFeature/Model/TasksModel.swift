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
    /// Matches on the server for this list and search, including rows not shown yet.
    var totalCount = 0
    var counts: TaskCounts?
    var phase: Phase = .loading
    var isRefreshing = false
    /// A refresh failed while the last good list stays on screen.
    var refreshFailed = false
    var error: WaiveraError?
    var showsRequests = false
    /// Requests waiting on this person, for the count in the Requests segment.
    var waitingCount = 0

    var rowCount: Int { sections.reduce(0) { $0 + $1.rows.count } }

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
/// the server to the person's role; My work is their own employee tasks. Each due group is its
/// own server list, so its count is the real total and opening more of it never depends on
/// scrolling past the others. Changing the segment, window, chip or search starts over with the
/// first rows of each group.
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
        var sections: [SectionLoad] = []
        var counts: TaskCounts?
        var phase: TasksScreenState.Phase = .loading
        var isRefreshing = false
        var refreshFailed = false
        var error: WaiveraError?
        /// The list scope `sections` belong to, so leaving Requests keeps a list that still fits.
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

    /// One due group's server list: the rows loaded so far, how many show, and its total.
    private struct SectionLoad: Equatable {
        var group: DueGroup
        var slice: TaskSlice
        var items: [TaskSummary] = []
        var total = 0
        var shown = TasksRules.sectionFirst
        var loading = false
        var failed = false

        func section(today: CalendarDate, me: String?, firstWeekday: Int) -> TaskSection {
            let visible = Array(items.prefix(shown))
            let hidden = total - visible.count
            let more: SectionMore? =
                if hidden > 0 {
                    .showMore(hidden: hidden, loading: loading, failed: failed)
                } else if total > TasksRules.sectionFirst {
                    .showFewer
                } else {
                    nil
                }
            return TaskSection(
                group: group,
                rows: visible.map { TasksRules.row($0, today: today, me: me, firstWeekday: firstWeekday) },
                total: total,
                more: more
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

    /// Shows up to `TasksRules.sectionStep` more of `group`, from rows already loaded or the next pages.
    func showMore(_ group: DueGroup) {
        guard let section = local.sections.first(where: { $0.group == group }), !section.loading,
            !local.isRefreshing, local.phase == .content
        else { return }
        let first = TasksRules.sectionFirst
        let target = min(section.shown + TasksRules.sectionStep, section.total)
        if target <= section.items.count {
            updateSection(group) {
                $0.shown = target
                $0.failed = false
            }
            return
        }
        updateSection(group) {
            $0.loading = true
            $0.failed = false
        }
        let listRequest = local.request
        let request = listRequest.sliced(section.slice)
        // One fresh read from the top, so a task closed on the web since the last page can't
        // shift the offsets and leave a row that no later page brings back.
        let size = (target + first - 1) / first * first
        let tasks = environment.tasks
        bag.replace("more-\(group)") { [weak self] in
            let result: Result<TaskPage, any Error>
            do {
                result = .success(try await tasks.tasks(request, page: 1, pageSize: size))
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled, self.local.request == listRequest else { return }
            self.updateSection(group) { current in
                current.loading = false
                guard case .success(let page) = result else {
                    current.failed = true
                    return
                }
                var known = Set<Int>()
                current.items = page.items.filter { known.insert($0.id).inserted }
                // A short page means the server has nothing past it, whatever its count says.
                current.total =
                    page.items.count < size ? current.items.count : max(page.totalCount, current.items.count)
                current.shown = max(min(target, current.items.count), first)
            }
        }
    }

    /// Folds `group` back to its first rows; the rows stay loaded for the next Show more.
    func showFewer(_ group: DueGroup) {
        updateSection(group) {
            $0.shown = TasksRules.sectionFirst
            $0.failed = false
        }
    }

    private func updateSection(_ group: DueGroup, _ change: (inout SectionLoad) -> Void) {
        guard let index = local.sections.firstIndex(where: { $0.group == group }) else { return }
        change(&local.sections[index])
        rebuild()
    }

    // MARK: Private

    private func reload(showSkeleton: Bool) {
        bag.replace("list") { [weak self] in await self?.load(showSkeleton: showSkeleton) }
    }

    private func load(showSkeleton: Bool) async {
        let request = local.request
        let zone = environment.calendar.scheduleTimeZone().zone
        let today = CalendarDate(environment.clock.now, in: zone)
        let plan = TasksRules.sectionPlan(request, today: today, firstWeekday: firstWeekday)
        // A refresh keeps how far each section was open; a new list starts every section closed.
        var previous: [DueGroup: Int] = [:]
        if !showSkeleton { for section in local.sections { previous[section.group] = section.shown } }
        if showSkeleton || local.phase == .error { local.phase = .loading }
        if showSkeleton {
            local.sections = []
            local.counts = nil
        }
        for group in DueGroup.allCases { bag.cancel("more-\(group)") }
        // Show more is cancelled, so no section may keep waiting on it.
        for index in local.sections.indices { local.sections[index].loading = false }
        local.isRefreshing = !showSkeleton
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
        let first = TasksRules.sectionFirst
        let results = await withTaskGroup(of: (Int, Result<TaskPage, any Error>).self) { taskGroup in
            for (index, (group, slice)) in plan.enumerated() {
                let sliced = request.sliced(slice)
                // Whole pages of `sectionFirst`, so a later Show more continues on the page after.
                let size = ((previous[group] ?? first) + first - 1) / first * first
                taskGroup.addTask {
                    do {
                        return (index, .success(try await tasks.tasks(sliced, page: 1, pageSize: size)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<TaskPage, any Error>)] = []
            for await result in taskGroup { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        guard !Task.isCancelled, local.request == request else { return }
        apply(results, plan: plan, previous: previous)
        rebuild()
    }

    /// The list after a reload: a section that failed keeps what it showed before; the others update.
    private func apply(
        _ results: [Result<TaskPage, any Error>],
        plan: [(DueGroup, TaskSlice)],
        previous: [DueGroup: Int]
    ) {
        let first = TasksRules.sectionFirst
        var failure: (any Error)?
        var sections: [SectionLoad] = []
        for ((group, slice), result) in zip(plan, results) {
            switch result {
            case .success(let page):
                var seen = Set<Int>()
                let items = page.items.filter { seen.insert($0.id).inserted }
                sections.append(
                    SectionLoad(
                        group: group,
                        slice: slice,
                        items: items,
                        total: max(page.totalCount, items.count),
                        // Never below the first rows, so a section that was empty still asks for a page.
                        shown: max(min(previous[group] ?? first, items.count), first)
                    )
                )
            case .failure(let error):
                failure = failure ?? error
                // Today's dates, so a later Show more on the kept rows asks for the right days.
                if var kept = local.sections.first(where: { $0.group == group }) {
                    kept.slice = slice
                    sections.append(kept)
                }
            }
        }
        local.sections = sections
        local.isRefreshing = false
        if sections.contains(where: { $0.total > 0 }) {
            local.phase = .content
        } else {
            local.phase = failure == nil ? .empty : .error
        }
        local.refreshFailed = failure != nil && local.phase == .content
        local.error = failure.map(WaiveraError.from)
        if local.refreshFailed { feedback.show(TasksStrings.text("tasks.refreshFailed"), retry: .refresh) }
    }

    private func rebuild() {
        let zone = environment.calendar.scheduleTimeZone().zone
        let today = CalendarDate(environment.clock.now, in: zone)
        let me = environment.session.currentState.user?.id
        var segment = local.segment
        if segment == .requests, access.loaded, !access.showsRequests { segment = .casework }
        var next = TasksScreenState()
        next.segment = segment
        next.window = local.window
        next.assignedToMe = local.assignedToMe
        next.delays = local.delays
        next.query = local.query
        next.sections = TasksRules.distinctRows(
            local.sections.filter { $0.total > 0 }
                .map { $0.section(today: today, me: me, firstWeekday: firstWeekday) }
        )
        next.totalCount = local.sections.reduce(0) { $0 + $1.total }
        next.counts = local.counts
        next.phase = local.phase
        next.isRefreshing = local.isRefreshing
        next.refreshFailed = local.refreshFailed
        next.error = local.error
        next.showsRequests = access.showsRequests
        next.waitingCount = access.showsRequests ? (waiting ?? []).filter { $0.kind.reviewableHere }.count : 0
        if next != state { state = next }
    }
}

extension TaskQuery {
    /// The same list, one section of it.
    func sliced(_ slice: TaskSlice) -> TaskQuery {
        var copy = self
        copy.slice = slice
        return copy
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
