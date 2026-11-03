import Foundation

/// What another tab asked the schedule to show: today in the Day view, or this week.
public enum ScheduleFocus: Hashable, Sendable {
    case today
    case thisWeek
}

/// One request to show a `ScheduleFocus`. `id` changes on every request, so asking for the same
/// focus again (after the person moved on) still applies.
public struct ScheduleFocusRequest: Hashable, Sendable {
    public var focus: ScheduleFocus
    public var id: Int

    public init(focus: ScheduleFocus, id: Int) {
        self.focus = focus
        self.id = id
    }
}
