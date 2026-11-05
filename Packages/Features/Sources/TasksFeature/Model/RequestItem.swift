import Foundation
import WaiveraAPI
import WaiveraData

/// A first and last day, or a from and to time; `end` is nil for one day.
struct TimeSpan: Hashable, Sendable {
    var start: String
    var end: String?

    /// "Tue, Nov 24 – Thu, Nov 26", or the one day or time alone.
    var text: String { end.map { TasksStrings.format("tasks.span", start, $0) } ?? start }
}

/// Time off asked for, or handed back by a cancellation.
struct TimeOffChange: Hashable, Sendable {
    var leaveType: String
    var dates: TimeSpan
    /// From and to clock times for a partial day, in the agency's leave zone.
    var times: TimeSpan?
    var minutes: Int
    var cancellation: Bool
}

/// One compared profile field, with dates already worded.
struct ProfileRow: Hashable, Sendable {
    var field: ProfileField.Field
    var previous: String?
    var requested: String?
}

/// The requester's balance around this time off, in minutes; `after` may go below zero.
struct BalanceChange: Hashable, Sendable {
    var before: Int
    var after: Int
}

/// What a request changes, already worded for the person's day.
enum RequestChange: Hashable, Sendable {
    /// More time: the due date moves from `from` to `to`, `daysLater` days later.
    case dueMove(from: String?, to: String, daysLater: Int?)
    /// A delay recorded for a server-owned period; the due date stays.
    case delayWindow(start: String, end: String)
    /// Closure: the task closes without being completed.
    case closure
    case timeOff(TimeOffChange)
    /// A participant's new details, changed fields first.
    case profile(changed: [ProfileRow], unchanged: [ProfileRow])
    /// A closed task opens again.
    case reopen
    /// A required file stops being required.
    case removeFile
    /// External training credit; its details load when the review opens.
    case training
    /// A kind newer than this app, reviewed on the web.
    case other

    var text: String? {
        switch self {
        case .dueMove(let from, let to, _):
            from.map { TasksStrings.format("tasks.change.dueMove", $0, to) }
                ?? TasksStrings.format("tasks.change.dueTo", to)
        case .delayWindow(let start, let end): TasksStrings.format("tasks.change.delay", start, end)
        case .closure: TasksStrings.text("tasks.change.closure")
        case .timeOff(let change):
            change.leaveType.isEmpty
                ? change.dates.text
                : TasksStrings.format("tasks.change.timeOff", change.leaveType, change.dates.text)
        case .profile(let changed, _):
            changed.isEmpty ? nil : TasksStrings.plural("tasks.review.changed", changed.count)
        case .reopen: TasksStrings.text("tasks.change.reopen")
        case .removeFile: TasksStrings.text("tasks.change.removeFile")
        case .training, .other: nil
        }
    }
}

struct RequestItem: Identifiable, Hashable, Sendable {
    var request: ChangeRequest
    /// When it was asked, in the employee's saved zone.
    var asked: TaskMoment?
    var change: RequestChange
    /// Today's due text for the task in question, when the request carries its current due date.
    var due: DueText
    var id: Int { request.id }

    var kindLabel: String { Self.kindLabel(request) }

    static func kindLabel(_ request: ChangeRequest) -> String {
        switch request.kind {
        case .moreTime: TasksStrings.text("tasks.kind.moreTime")
        case .delay: TasksStrings.text("tasks.kind.delay")
        case .closure: TasksStrings.text("tasks.kind.closure")
        case .timeOff: TasksStrings.text("tasks.kind.timeOff")
        case .timeOffCancellation: TasksStrings.text("tasks.kind.timeOffCancel")
        case .profileChange: TasksStrings.text("tasks.kind.profile")
        case .reactivation: TasksStrings.text("tasks.kind.reopen")
        case .attachmentRemoval: TasksStrings.text("tasks.kind.removeFile")
        case .trainingCredit: TasksStrings.text("tasks.kind.training")
        case .other: request.typeName
        }
    }

    var statusLabel: String {
        switch request.status {
        case .approved: TasksStrings.text("tasks.status.approved")
        case .rejected: TasksStrings.text("tasks.status.rejected")
        case .pending, .other: TasksStrings.text("tasks.status.pending")
        }
    }

    var reviewTitle: String {
        switch request.kind {
        case .moreTime: TasksStrings.text("tasks.review.title.moreTime")
        case .delay: TasksStrings.text("tasks.review.title.delay")
        case .closure: TasksStrings.text("tasks.review.title.closure")
        default: kindLabel
        }
    }

    /// The confirm sheet's title and what will happen, worded as the web's review dialogs are.
    func confirmation(approve: Bool) -> (title: String, message: String) {
        let task = request.taskTitle ?? TasksStrings.text("tasks.thisTask")
        let who = request.requesterName.isEmpty ? TasksStrings.text("tasks.theRequester") : request.requesterName
        let verb = approve ? "approve" : "reject"
        switch (request.kind, change) {
        case (.moreTime, .dueMove(let from, let to, _)):
            let title = TasksStrings.text("tasks.confirm.\(verb).title.moreTime")
            if approve {
                let message =
                    from.map { TasksStrings.format("tasks.confirm.approve.moreTime", task, to, $0, who) }
                    ?? TasksStrings.format("tasks.confirm.approve.moreTime.short", task, to, who)
                return (title, message)
            }
            let message =
                from.map { TasksStrings.format("tasks.confirm.reject.moreTime", task, $0, who) }
                ?? TasksStrings.format("tasks.confirm.reject.moreTime.short", task, who)
            return (title, message)
        case (.moreTime, _):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.moreTime"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.generic", task, who)
                    : TasksStrings.format("tasks.confirm.reject.moreTime.short", task, who)
            )
        case (.delay, .delayWindow(let start, let end)):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.delay"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.delay", start, end, task, who)
                    : TasksStrings.format("tasks.confirm.reject.delay", task, who)
            )
        case (.delay, _):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.delay"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.generic", task, who)
                    : TasksStrings.format("tasks.confirm.reject.delay", task, who)
            )
        case (.timeOff, _), (.timeOffCancellation, _):
            let dates: String = if case .timeOff(let time) = change { time.dates.text } else { "" }
            let kind = request.kind == .timeOffCancellation ? "cancel" : "timeOff"
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.\(kind)"),
                TasksStrings.format("tasks.confirm.\(verb).\(kind)", who, dates)
            )
        case (.profileChange, _):
            let count: Int = if case .profile(let fields, _) = change { fields.count } else { 0 }
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.profile"),
                approve
                    ? TasksStrings.plural("tasks.confirm.approve.profile", count)
                    : TasksStrings.format("tasks.confirm.reject.profile", who)
            )
        case (.reactivation, _):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.reopen"),
                TasksStrings.format("tasks.confirm.\(verb).reopen", task, who)
            )
        case (.attachmentRemoval, _):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.removeFile"),
                TasksStrings.format("tasks.confirm.\(verb).removeFile", task, who)
            )
        case (.trainingCredit, _):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.training"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.training", who)
                    : TasksStrings.text("tasks.confirm.reject.training")
            )
        default:
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.closure"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.closure", task, who)
                    : TasksStrings.format("tasks.confirm.reject.closure", task, who)
            )
        }
    }
}

/// Builds request items (Android `RequestsViewModel.item`): what changes, worded for today.
enum RequestItems {
    private static let dateFields: Set<ProfileField.Field> = [.dateOfBirth, .certification, .cpocStart, .cpocEnd]

    /// `leaveZone` words partial days, as on the web; the person's own zone stands in for it.
    static func item(
        _ request: ChangeRequest,
        zone: TimeZone,
        leaveZone: TimeZone,
        today: CalendarDate
    ) -> RequestItem {
        RequestItem(
            request: request,
            asked: request.requestedAt.map { TaskFormat.moment($0, zone: zone, today: today) },
            change: change(request, leaveZone: leaveZone, today: today),
            due: TaskFormat.due(request.currentDue, today: today)
        )
    }

    static func change(_ request: ChangeRequest, leaveZone: TimeZone, today: CalendarDate) -> RequestChange {
        switch request.kind {
        case .moreTime:
            guard let to = request.requestedDue else { return .other }
            let later = request.currentDue.map { $0.days(until: to) }.flatMap { $0 > 0 ? $0 : nil }
            return .dueMove(
                from: request.currentDue.map { TaskFormat.date($0, today: today) },
                to: TaskFormat.date(to, today: today),
                daysLater: later
            )
        case .delay:
            guard let start = request.delayStart, let end = request.delayEnd else { return .other }
            return .delayWindow(start: TaskFormat.date(start, today: today), end: TaskFormat.date(end, today: today))
        case .closure:
            return .closure
        case .timeOff, .timeOffCancellation:
            guard let time = request.timeOff else { return .other }
            return timeOff(time, cancellation: request.kind == .timeOffCancellation, zone: leaveZone, today: today)
        case .profileChange:
            return profile(request.profile, today: today)
        case .reactivation:
            return .reopen
        case .attachmentRemoval:
            return .removeFile
        case .trainingCredit:
            return .training
        case .other:
            return .other
        }
    }

    static func timeOff(_ time: TimeOffReview, cancellation: Bool, zone: TimeZone, today: CalendarDate)
        -> RequestChange
    {
        var times: TimeSpan?
        var startDay = time.startDate
        var endDay = time.endDate
        if time.partialDay, let start = time.start, let end = time.end {
            startDay = CalendarDate(start, in: zone)
            endDay = CalendarDate(end, in: zone)
            times = TimeSpan(start: TaskFormat.time(start, zone: zone), end: TaskFormat.time(end, zone: zone))
        }
        guard let startDay else { return .other }
        let dates =
            if let endDay, endDay != startDay {
                TimeSpan(start: TaskFormat.date(startDay, today: today), end: TaskFormat.date(endDay, today: today))
            } else {
                TimeSpan(start: TaskFormat.date(startDay, today: today), end: nil)
            }
        return .timeOff(
            TimeOffChange(
                leaveType: time.leaveType,
                dates: dates,
                times: times,
                minutes: time.minutes,
                cancellation: cancellation
            )
        )
    }

    static func profile(_ fields: [ProfileField], today: CalendarDate) -> RequestChange {
        let rows = fields.map { field -> (Bool, ProfileRow) in
            let format = { (value: String?) -> String? in
                guard let value, dateFields.contains(field.field) else { return value }
                return CalendarDate(parsing: value).map(TaskFormat.fullDate) ?? value
            }
            let row = ProfileRow(
                field: field.field,
                previous: format(field.previous),
                requested: format(field.requested)
            )
            return (field.changed, row)
        }
        return .profile(changed: rows.filter(\.0).map(\.1), unchanged: rows.filter { !$0.0 }.map(\.1))
    }

    /// sprout_web `renderTimeOffDetails`: a pending request already holds its minutes.
    static func balance(_ balance: LeaveBalance?, timeOff: TimeOffReview, cancellation: Bool) -> BalanceChange? {
        guard let balance, balance.tracksBalance else { return nil }
        return cancellation
            ? BalanceChange(before: balance.availableMinutes, after: balance.availableMinutes + timeOff.minutes)
            : BalanceChange(before: balance.availableMinutes + timeOff.minutes, after: balance.availableMinutes)
    }

    /// "2 hrs", "1.5 hrs", "-3.25 hrs": at most two decimals, as the web shows hours.
    static func hours(minutes: Int) -> String { hours(Double(minutes) / 60) }

    static func hours(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        var label = String(format: "%.2f", rounded)
        while label.hasSuffix("0") { label.removeLast() }
        if label.hasSuffix(".") { label.removeLast() }
        if label == "-0" { label = "0" }
        return TasksStrings.format(rounded == 1 ? "tasks.review.hours.one" : "tasks.review.hours.other", label)
    }
}
