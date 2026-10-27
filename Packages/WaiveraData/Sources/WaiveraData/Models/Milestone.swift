import Foundation
import WaiveraAPI

/// A birthday or work anniversary; recurs every year (07 §2).
public struct Milestone: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case birthday, workAnniversary
    }

    public var kind: Kind
    public var userId: String
    public var displayName: String?
    public var avatarURL: String?
    /// 1-based.
    public var month: Int
    public var day: Int
    public var startYear: Int?

    public init(
        kind: Kind,
        userId: String,
        displayName: String?,
        month: Int,
        day: Int,
        startYear: Int? = nil,
        avatarURL: String? = nil
    ) {
        self.kind = kind
        self.userId = userId
        self.displayName = displayName
        self.month = month
        self.day = day
        self.startYear = startYear
        self.avatarURL = avatarURL
    }

    /// The date it falls on in `year`; Feb 29 moves to Feb 28 outside leap years.
    public func occurrence(in year: Int) -> CalendarDate? {
        let effectiveDay = month == 2 && day == 29 && !CalendarDate.isLeapYear(year) ? 28 : day
        return CalendarDate(year: year, month: month, day: effectiveDay)
    }

    /// Completed years on `date` for anniversaries; `nil` when not one or under a year.
    public func years(on date: CalendarDate) -> Int? {
        guard kind == .workAnniversary, let startYear else { return nil }
        let years = date.year - startYear
        return years >= 1 ? years : nil
    }

    public func falls(on date: CalendarDate) -> Bool {
        guard occurrence(in: date.year) == date else { return false }
        return kind == .birthday || years(on: date) != nil
    }
}

/// What an avatar or agenda card celebrates today (07 §4). Copy is built by the screen.
public struct Celebration: Sendable, Hashable {
    public var userId: String
    public var displayName: String?
    public var avatarURL: String?
    public var isBirthday: Bool
    public var anniversaryYears: Int?

    public enum Kind: Sendable, Hashable {
        case birthday, anniversary, both
    }

    public var kind: Kind {
        switch (isBirthday, anniversaryYears) {
        case (true, .some): .both
        case (true, .none): .birthday
        default: .anniversary
        }
    }
}

/// Milestones indexed once per list change, so avatars and grid cells are O(1) (07 §4).
public struct MilestoneIndex: Sendable, Hashable {
    public let milestones: [Milestone]
    private let byUser: [String: [Milestone]]

    public init(_ milestones: [Milestone]) {
        self.milestones = milestones
        byUser = Dictionary(grouping: milestones, by: \.userId)
    }

    public static let empty = MilestoneIndex([])

    /// Everyone celebrating on `date` (a date in the employee's zone), ordered by name.
    public func celebrations(on date: CalendarDate) -> [Celebration] {
        byUser.keys.compactMap { celebration(for: $0, on: date) }
            .sorted { ($0.displayName ?? "", $0.userId) < ($1.displayName ?? "", $1.userId) }
    }

    public func celebration(for userId: String, on date: CalendarDate) -> Celebration? {
        let matches = (byUser[userId] ?? []).filter { $0.falls(on: date) }
        guard let first = matches.first else { return nil }
        let birthday = matches.contains { $0.kind == .birthday }
        let years = matches.compactMap { $0.years(on: date) }.first
        return Celebration(
            userId: userId,
            displayName: first.displayName,
            avatarURL: first.avatarURL,
            isBirthday: birthday,
            anniversaryYears: years
        )
    }
}
