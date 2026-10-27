import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// Everything the Schedule tab draws, already formatted. Dates are literal dates in the
/// schedule zone.
public struct ScheduleUIState: Sendable, Hashable {
    public var view: CalendarPeriod
    public var selectedDate: CalendarDate
    public var today: CalendarDate
    public var zoneIdentifier: String
    /// "Times shown in Central Time", or the fallback sentence; nil when nothing needs saying.
    public var zoneNotice: String?
    public var title: String
    public var weekdayHeaders: [String]
    public var cells: [GridCell]
    public var agendaHeading: String
    public var agenda: AgendaState
    public var isRefreshing: Bool
    /// A refresh failed while saved data is on screen: a banner with Retry, never a full error.
    public var feedNotice: String?
    /// Milestones failed to load; the calendar still renders and a quiet banner says so.
    public var milestonesFailed: Bool

    public var isTodaySelected: Bool { selectedDate == today }
}

/// One grid cell. `inPeriod` is false for month spill days, which still show their dots.
public struct GridCell: Sendable, Hashable, Identifiable {
    public var date: CalendarDate
    public var dayNumber: String
    public var weekday: String
    public var inPeriod: Bool
    public var isToday: Bool
    public var isSelected: Bool
    public var marker: DayMarker
    /// "Sunday, November 1, today, 2 events, 1 celebration".
    public var accessibilityLabel: String

    public var id: String { date.isoString }
}

public enum AgendaState: Sendable, Hashable {
    /// Nothing to show yet; the screen shows the skeleton after ~300 ms.
    case loading
    /// The first load failed and nothing is saved.
    case error(WaiveraError)
    case empty
    case content([AgendaRow])
}

/// One agenda card, formatted.
public struct AgendaRow: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case celebration(ScheduleCelebration)
        case holiday
        case timeOff
        /// Tapping opens the event screen.
        case event(id: String)
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var accessibilityLabel: String
    /// The event owner's colour for the card's leading bar; nil uses the accent token.
    public var ownerColor: RGBColor?
}
