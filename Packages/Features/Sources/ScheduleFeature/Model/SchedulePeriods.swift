import Foundation
import WaiveraAPI
import WaiveraData

/// How the navigator title reads for the current period (07 §1 "Period title").
public enum PeriodTitle: Sendable, Hashable {
    /// "October 2026".
    case month(CalendarDate)
    /// "Tue, October 27".
    case day(CalendarDate)
    /// "October 25–31, 2026".
    case weekInMonth(start: CalendarDate, end: CalendarDate)
    /// "October 28 – November 3", without a year.
    case weekAcrossMonths(start: CalendarDate, end: CalendarDate)
}

public extension PeriodTitle {
    /// The first day the title covers.
    var startDate: CalendarDate {
        switch self {
        case .month(let date), .day(let date): date
        case .weekInMonth(let start, _), .weekAcrossMonths(let start, _): start
        }
    }

    /// Which way the period moved from `previous`: 1 forward, -1 back, 0 when the view changed
    /// or the period stayed (a day picked in the same month swaps in place).
    func stepDirection(from previous: PeriodTitle) -> Int {
        guard kind == previous.kind else { return 0 }
        let delta = startDate.daysSinceEpoch - previous.startDate.daysSinceEpoch
        return delta == 0 ? 0 : (delta > 0 ? 1 : -1)
    }

    private var kind: Int {
        switch self {
        case .month: 0
        case .day: 1
        case .weekInMonth, .weekAcrossMonths: 2
        }
    }
}

/// Period maths for the schedule. Every value is a literal date in the schedule zone; instants
/// appear only at the repository boundary (`CalendarPeriod.fetchInterval`).
public enum SchedulePeriods {
    /// Month stepping keeps the day but never past the 28th, so 31 Jan steps to 28 Feb, then 28 Mar.
    static let monthStepMaxDay = 28

    /// Cells the grid draws: 42 for month, 7 for week, none for day.
    public static func cells(_ view: CalendarPeriod, containing date: CalendarDate) -> [CalendarDate] {
        view == .day ? [] : view.dates(containing: date)
    }

    /// The selected date after Previous (-1) or Next (+1).
    public static func step(_ view: CalendarPeriod, from date: CalendarDate, by direction: Int) -> CalendarDate {
        switch view {
        case .day:
            return date.adding(days: direction)
        case .week:
            return date.adding(days: 7 * direction)
        case .month:
            let month = date.firstOfMonth.addingMonths(direction)
            return CalendarDate(year: month.year, month: month.month, day: min(date.day, monthStepMaxDay)) ?? month
        }
    }

    /// The fetched range: the whole rendered grid, so month spill days get their dots (07 §2 fix).
    public static func fetchInterval(
        _ view: CalendarPeriod,
        containing date: CalendarDate,
        in zone: TimeZone
    ) -> DateInterval {
        view.fetchInterval(containing: date, in: zone)
    }

    public static func title(_ view: CalendarPeriod, for date: CalendarDate) -> PeriodTitle {
        switch view {
        case .month:
            return .month(date.firstOfMonth)
        case .day:
            return .day(date)
        case .week:
            let start = date.startOfWeek
            let end = start.adding(days: 6)
            return start.month == end.month && start.year == end.year
                ? .weekInMonth(start: start, end: end)
                : .weekAcrossMonths(start: start, end: end)
        }
    }

    /// Whether `cell` belongs to the period: false only for month-grid spill days.
    public static func isInPeriod(_ cell: CalendarDate, view: CalendarPeriod, anchor: CalendarDate) -> Bool {
        view != .month || (cell.year == anchor.year && cell.month == anchor.month)
    }
}
