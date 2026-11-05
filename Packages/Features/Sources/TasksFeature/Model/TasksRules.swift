import Foundation
import WaiveraAPI
import WaiveraData

/// The Tasks tab's segments. Requests shows only to people the web shows Admin Requests to.
public enum TasksSegment: Hashable, Sendable, CaseIterable {
    case casework
    case myWork
    case requests
}

/// How the list groups cards, in display order. A task under an approved delay sits in
/// `delayed` whatever its due date, so `overdue` only holds work that is really late.
enum DueGroup: Int, Hashable, Sendable, Comparable, CaseIterable {
    case overdue
    case delayed
    case thisWeek
    case nextWeek
    case later
    case noDue

    static func < (lhs: DueGroup, rhs: DueGroup) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .overdue: TasksStrings.text("tasks.group.overdue")
        case .delayed: TasksStrings.text("tasks.group.delayed")
        case .thisWeek: TasksStrings.text("tasks.group.thisWeek")
        case .nextWeek: TasksStrings.text("tasks.group.nextWeek")
        case .later: TasksStrings.text("tasks.group.later")
        case .noDue: TasksStrings.text("tasks.group.noDue")
        }
    }
}

/// At most one badge per card: a closure request first, then the work state.
enum RowFlag: Hashable, Sendable {
    case closureRequested
    case inProgress
    case inReview
}

/// One task card, already worded for the person's day.
struct TaskRow: Identifiable, Hashable, Sendable {
    var id: Int
    var key: String
    var title: String
    var about: String?
    var due: DueText
    var state: TaskState
    /// The date tile: month and day of the due date, or nil without one.
    var tileMonth: String?
    var tileDay: String?
    /// Whole days past due; nil when not overdue or when a delay covers it.
    var daysLate: Int?
    /// An approved delay covers today: the card reads "Delayed through …" instead of late.
    var delayed: Bool
    var delayedThrough: String?
    /// Someone else owns it; nil when it is the person's own.
    var assignee: String?
    var flag: RowFlag?
    var group: DueGroup

    /// The line under the title: due text, then who it is about.
    var dueLine: String {
        if delayed {
            return delayedThrough.map { TasksStrings.format("tasks.row.delayedThrough", $0) }
                ?? TasksStrings.text("tasks.row.delayed")
        }
        if let daysLate { return TasksStrings.plural("tasks.row.daysLate", daysLate) }
        return due.text
    }

    var accessibilityLabel: String {
        [title, key, about, dueLine, assignee.map { TasksStrings.format("tasks.row.assignedTo", $0) }]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// One due group as the list shows it: the first `rows` of the server's `total` for that group.
/// `more` is the button under it, or nil when the whole group fits in the first rows.
struct TaskSection: Identifiable, Hashable, Sendable {
    var group: DueGroup
    var rows: [TaskRow]
    var total: Int
    var more: SectionMore?
    var id: DueGroup { group }

    init(group: DueGroup, rows: [TaskRow], total: Int? = nil, more: SectionMore? = nil) {
        self.group = group
        self.rows = rows
        self.total = total ?? rows.count
        self.more = more
    }
}

/// The button under a capped section (Android `SectionMore`).
enum SectionMore: Hashable, Sendable {
    /// `hidden` tasks are not shown yet; a tap shows up to `TasksRules.sectionStep` more.
    case showMore(hidden: Int, loading: Bool = false, failed: Bool = false)
    /// Everything is open; a tap folds the section back to its first rows.
    case showFewer
}

enum TasksRules {
    static func row(_ task: TaskSummary, today: CalendarDate, me: String?, firstWeekday: Int) -> TaskRow {
        let due = task.due
        var late: Int?
        if let due, !task.delayed, due < today { late = due.days(until: today) }
        let flag: RowFlag? =
            if task.pendingClosure {
                .closureRequested
            } else if task.state == .inProgress {
                .inProgress
            } else if task.state == .inReview {
                .inReview
            } else {
                nil
            }
        let mine = task.assigneeId != nil && task.assigneeId == me
        return TaskRow(
            id: task.id,
            key: task.key,
            title: task.title,
            about: task.about,
            due: TaskFormat.due(due, today: today),
            state: task.state,
            tileMonth: due.map(TaskFormat.tileMonth),
            tileDay: due.map { String($0.day) },
            daysLate: late,
            delayed: task.delayed,
            delayedThrough: task.delayedThrough.map { TaskFormat.shortDate($0, today: today) },
            assignee: mine ? nil : task.assigneeName,
            flag: flag,
            group: task.delayed ? .delayed : group(due, today: today, firstWeekday: firstWeekday)
        )
    }

    /// Weeks start on the locale's first day (1 = Sunday), as the phone's own calendar does.
    static func group(_ due: CalendarDate?, today: CalendarDate, firstWeekday: Int) -> DueGroup {
        guard let due else { return .noDue }
        if due < today { return .overdue }
        let back = (today.weekday - firstWeekday + 7) % 7
        let weekStart = today.adding(days: -back)
        let nextWeek = weekStart.adding(days: 7)
        if due < nextWeek { return .thisWeek }
        if due < nextWeek.adding(days: 7) { return .nextWeek }
        return .later
    }

    /// Rows each section opens with (Sheldon, 2026-11-05).
    static let sectionFirst = 5
    /// Rows each Show more adds.
    static let sectionStep = 10

    /// The sections a list asks the server for, in display order, with the same week edges as
    /// `group`. Delayed casework is one section of its own; every other section leaves it out.
    static func sectionPlan(_ query: TaskQuery, today: CalendarDate, firstWeekday: Int) -> [(DueGroup, TaskSlice)] {
        let casework = query.scope == .casework
        let delayed = casework && query.delays != .hide
        let others = !(casework && query.delays == .only)
        let back = (today.weekday - firstWeekday + 7) % 7
        let nextWeek = today.adding(days: 7 - back)
        var plan: [(DueGroup, TaskSlice)] = []
        if others, query.window != .dueSoon { plan.append((.overdue, TaskSlice(dueTo: today.adding(days: -1)))) }
        if delayed { plan.append((.delayed, TaskSlice(delayed: true))) }
        if others, query.window != .overdue {
            plan.append((.thisWeek, TaskSlice(dueFrom: today, dueTo: nextWeek.adding(days: -1))))
            plan.append((.nextWeek, TaskSlice(dueFrom: nextWeek, dueTo: nextWeek.adding(days: 6))))
            plan.append((.later, TaskSlice(dueFrom: nextWeek.adding(days: 7))))
        }
        return plan
    }

    /// A task in two sections at once (the server moved it between two section loads) shows only
    /// in the first, as the list keys rows by task id.
    static func distinctRows(_ sections: [TaskSection]) -> [TaskSection] {
        var seen = Set<Int>()
        return sections.map { section in
            var copy = section
            copy.rows = section.rows.filter { seen.insert($0.id).inserted }
            return copy
        }
    }
}
