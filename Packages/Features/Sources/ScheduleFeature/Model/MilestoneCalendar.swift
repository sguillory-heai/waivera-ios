import Foundation
import WaiveraAPI
import WaiveraData

/// One person's celebration on a date (07 §4 `EmployeeCelebration`).
public struct ScheduleCelebration: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case birthday, anniversary, both
    }

    public let userId: String
    public let displayName: String?
    public let avatarURL: String?
    public let kind: Kind
    /// Completed years, set whenever an anniversary is part of the celebration.
    public let years: Int?

    public var id: String { userId }

    public init(userId: String, displayName: String?, avatarURL: String? = nil, kind: Kind, years: Int?) {
        self.userId = userId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.kind = kind
        self.years = years
    }

    init(_ celebration: Celebration) {
        let kind: Kind =
            switch celebration.kind {
            case .birthday: .birthday
            case .anniversary: .anniversary
            case .both: .both
            }
        self.init(
            userId: celebration.userId,
            displayName: celebration.displayName,
            avatarURL: celebration.avatarURL,
            kind: kind,
            years: celebration.anniversaryYears
        )
    }
}

/// Milestones indexed by month/day as well as by person, built once per milestone list, so the
/// 42 cells of a month grid look up their celebrations without scanning everyone (07 §4
/// performance note). Resolution (Feb 29 on Feb 28 in common years, anniversaries need a start
/// year and one full year) stays in `MilestoneIndex` and `Milestone.falls(on:)`.
///
/// Dates passed in are literal dates in the schedule zone; nothing here reads a clock.
public struct MilestoneCalendar: Sendable {
    public let index: MilestoneIndex
    private let byMonthDay: [Int: [String]]

    public init(_ index: MilestoneIndex) {
        self.index = index
        var byMonthDay: [Int: Set<String>] = [:]
        for milestone in index.milestones {
            byMonthDay[Self.key(month: milestone.month, day: milestone.day), default: []].insert(milestone.userId)
        }
        self.byMonthDay = byMonthDay.mapValues { $0.sorted() }
    }

    public static let empty = MilestoneCalendar(.empty)

    public var isEmpty: Bool { index.milestones.isEmpty }

    /// People who could be celebrating on `date`; the only ones `celebrations(on:)` evaluates.
    func candidates(on date: CalendarDate) -> [String] {
        var users = byMonthDay[Self.key(month: date.month, day: date.day)] ?? []
        if date.month == 2, date.day == 28, !CalendarDate.isLeapYear(date.year) {
            users += byMonthDay[Self.key(month: 2, day: 29)] ?? []
        }
        return users
    }

    /// Everyone celebrating on `date`, birthdays first, then by name.
    public func celebrations(on date: CalendarDate) -> [ScheduleCelebration] {
        Set(candidates(on: date)).compactMap { celebration(for: $0, on: date) }
            .sorted { lhs, rhs in
                (lhs.sortRank, lhs.displayName ?? "", lhs.userId) < (rhs.sortRank, rhs.displayName ?? "", rhs.userId)
            }
    }

    public func count(on date: CalendarDate) -> Int {
        Set(candidates(on: date)).filter { index.celebration(for: $0, on: date) != nil }.count
    }

    /// The badge for one person on `date`, or nil when there is nothing to celebrate.
    public func celebration(for userId: String?, on date: CalendarDate) -> ScheduleCelebration? {
        guard let userId, !userId.isEmpty, let celebration = index.celebration(for: userId, on: date) else {
            return nil
        }
        return ScheduleCelebration(celebration)
    }

    private static func key(month: Int, day: Int) -> Int { month * 100 + day }
}

extension ScheduleCelebration {
    fileprivate var sortRank: Int {
        switch kind {
        case .birthday, .both: 0
        case .anniversary: 1
        }
    }
}
