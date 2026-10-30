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
    /// The period the title names; a change of its start says which way a step went.
    public var period: PeriodTitle
    /// The Day title with a short month ("Sun, Nov 1"), for the largest text sizes.
    public var shortTitle: String
    public var weekdayHeaders: [String]
    public var cells: [GridCell]
    public var agendaHeading: String
    /// The agenda heading with a short month, for the largest text sizes (UI10-09).
    public var agendaHeadingShort: String
    public var agenda: AgendaState
    public var isRefreshing: Bool
    /// A refresh failed while saved data is on screen: a banner with Retry, never a full error.
    public var feedNotice: String?
    /// Milestones failed to load; the calendar still renders and a quiet banner says so.
    public var milestonesFailed: Bool
    /// Where "now" falls in today's agenda; nil on other days or with nothing timed.
    public var agendaNow: AgendaNowMarker?
    /// The celebrant whose direct chat is opening from "Send wishes".
    public var openingWishesFor: String?
    /// The profile has no usable zone: the notice is an info banner, not a caption.
    public var isFallbackZone = false
    /// Which way the last change moved the period: 1 forward, -1 back, 0 for a view change or a
    /// day picked in the same period. The grid, title and agenda heading slide this way.
    public var periodStep = 0

    public var isTodaySelected: Bool { selectedDate == today }

    /// "Today" is offered only when today is out of sight, so it never sits in the bar doing
    /// nothing on first open (UI2-07).
    public var showsJumpToToday: Bool {
        switch view {
        case .day: selectedDate != today
        case .week, .month: !cells.contains { $0.inPeriod && $0.isToday }
        }
    }
}

/// The "Now · 10:30 AM" line in today's agenda (UI4-12): it goes before the row `beforeID` (after
/// the last row when nil), and the rows in `endedIDs` are drawn quieter. The time is in the
/// schedule zone.
public struct AgendaNowMarker: Sendable, Hashable {
    public var time: String
    public var beforeID: String?
    public var endedIDs: Set<String>
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
    /// "Organized by Alex Rivera" on an event card; nil when the owner is unknown.
    public var owner: String?
    /// An online or Sprout meeting: the tile shows a camera instead of a clock.
    public var isOnline = false
    /// What the Day view's timeline rail says beside the card.
    public var rail = AgendaRail(time: "", kicker: nil)
    /// The celebration emoji for the card's own tile.
    public var emoji: String?
    /// The signed-in person's own celebration: no "Send wishes" on it.
    public var isMine = false
}

/// The Day view's rail beside one card: the start time, "Until" over the end of an item that
/// began the day before, or "All day". The kicker sits over the time so the column never wraps
/// "Until 6:00 / AM" (UI10-11).
public struct AgendaRail: Sendable, Hashable {
    public var time: String
    public var kicker: String?
}

/// The rail block's colour (concept B's "Your day"): teal for events, gold for celebrations,
/// violet for time off and holidays; an ended item has none.
public enum AgendaRailTone: Sendable, Hashable {
    case teal, gold, violet

    public static func of(_ kind: AgendaRow.Kind, ended: Bool) -> AgendaRailTone? {
        if ended { return nil }
        switch kind {
        case .event: return .teal
        case .celebration: return .gold
        case .holiday, .timeOff: return .violet
        }
    }
}
