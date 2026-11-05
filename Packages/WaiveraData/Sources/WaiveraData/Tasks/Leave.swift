import Foundation

/// One of the agency's leave types, with the person's balance for it when it keeps one.
public struct LeaveType: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var tracksBalance: Bool
    /// Minutes the person can still request; nil when the balance couldn't be read.
    public var availableMinutes: Int?

    public init(id: Int, name: String, tracksBalance: Bool, availableMinutes: Int?) {
        self.id = id
        self.name = name
        self.tracksBalance = tracksBalance
        self.availableMinutes = availableMinutes
    }
}

/// Time off as the person filled it in. A full day runs from the first day's midnight to the
/// last day's end in UTC calendar terms (sprout_web `AdminRequestModal`); a partial day is two
/// instants on one day in the person's saved zone.
public struct LeaveDraft: Sendable, Hashable {
    public var leaveTypeId: Int
    public var partialDay: Bool
    public var start: Date
    public var end: Date
    public var note: String?

    public init(leaveTypeId: Int, partialDay: Bool, start: Date, end: Date, note: String?) {
        self.leaveTypeId = leaveTypeId
        self.partialDay = partialDay
        self.start = start
        self.end = end
        self.note = note
    }
}

/// Why the server says there is nothing to request (`BuildBlockedPreview` codes).
public enum LeaveBlock: Sendable, Hashable { case weekend, holiday, overlap, other }

/// sprout_api `PreviewRequestAsync`: the hours this asks for and the balance around it.
public struct LeavePreview: Sendable, Hashable {
    public var requestedMinutes: Int
    public var tracksBalance: Bool
    public var beforeMinutes: Int?
    public var afterMinutes: Int?
    /// Set when the dates hold no requestable hours; sending is off.
    public var block: LeaveBlock?
    public var impact: LeaveImpact?

    public init(
        requestedMinutes: Int,
        tracksBalance: Bool,
        beforeMinutes: Int?,
        afterMinutes: Int?,
        block: LeaveBlock?,
        impact: LeaveImpact?
    ) {
        self.requestedMinutes = requestedMinutes
        self.tracksBalance = tracksBalance
        self.beforeMinutes = beforeMinutes
        self.afterMinutes = afterMinutes
        self.block = block
        self.impact = impact
    }
}

/// Why a send was refused, worded by the app rather than the server.
public enum LeaveSendProblem: Sendable, Hashable {
    case notEnoughBalance, probation, weekend, holiday, noWorkdays, overlap, other
}

/// A refused time-off send; `problem` picks the app's wording.
public struct LeaveSendError: Error, Sendable, Hashable {
    public var problem: LeaveSendProblem

    public init(problem: LeaveSendProblem) { self.problem = problem }
}
