import Foundation
import WaiveraAPI
import WaiveraData

/// Pure mapping from repository values to `ScheduleUIState`, shared by the model and previews.
struct ScheduleStateBuilder {
    var view: CalendarPeriod
    var selectedDate: CalendarDate
    var today: CalendarDate
    var zone: ScheduleZone
    var deviceZone: TimeZone
    /// The feed for exactly this period and zone, or nil while it is not known.
    var feed: Resource<CalendarFeed>?
    var milestones: MilestoneCalendar
    var milestonesFailed: Bool
    var isOffline: Bool
    /// The current instant, for today's "Now" line and the ended cards.
    var now: Date?
    /// The signed-in person, whose own celebration card offers no "Send wishes".
    var myUserId: String?
    var openingWishesFor: String?

    func build(text: ScheduleText) -> ScheduleUIState {
        let feedValue = feed?.value ?? CalendarFeed()
        let cellDates = SchedulePeriods.cells(view, containing: selectedDate)
        let markers = ScheduleAgenda.markers(
            feed: feedValue,
            zone: zone.timeZone,
            milestones: milestones,
            cells: cellDates
        )
        let cells = cellDates.map { date in
            let inPeriod = SchedulePeriods.isInPeriod(date, view: view, anchor: selectedDate)
            let marker = markers[date] ?? DayMarker()
            return GridCell(
                date: date,
                dayNumber: text.dayNumber(date),
                weekday: text.weekdayShort(date),
                weekdayNarrow: text.weekdayNarrow(date),
                inPeriod: inPeriod,
                isToday: date == today,
                isSelected: date == selectedDate,
                marker: marker,
                accessibilityLabel: Self.cellLabel(date, today: today, inPeriod: inPeriod, marker: marker, text: text)
            )
        }
        let title = SchedulePeriods.title(view, for: selectedDate)
        let content = agendaContent(feedValue, text: text)
        return ScheduleUIState(
            view: view,
            selectedDate: selectedDate,
            today: today,
            zoneIdentifier: zone.identifier,
            zoneNotice: Self.zoneNotice(zone: zone, deviceZone: deviceZone, text: text),
            title: text.title(title),
            period: title,
            shortTitle: view == .day ? text.weekdayShortMonthDay(selectedDate) : text.title(title),
            weekdayHeaders: text.weekdayHeaders,
            weekdayHeadersNarrow: text.weekdayHeadersNarrow,
            cells: cells,
            agendaHeading: text.fullDay(selectedDate),
            agendaHeadingShort: text.weekdayShortMonthDay(selectedDate),
            agenda: content.state,
            isRefreshing: feed?.isRefreshing ?? false,
            feedNotice: feedNotice,
            milestonesFailed: milestonesFailed,
            agendaNow: content.now,
            openingWishesFor: openingWishesFor,
            isFallbackZone: zone.isFallback
        )
    }

    private var feedNotice: String? {
        guard let feed, feed.value != nil, feed.error != nil else { return nil }
        return ScheduleStrings.text(isOffline ? "schedule.offline" : "schedule.refreshFailed")
    }

    private func agendaContent(
        _ value: CalendarFeed,
        text: ScheduleText
    ) -> (state: AgendaState, now: AgendaNowMarker?) {
        guard let feed else { return (.loading, nil) }
        if feed.value == nil {
            if let error = feed.error { return (.error(error), nil) }
            return (.loading, nil)
        }
        let items = ScheduleAgenda.items(feed: value, zone: zone.timeZone, milestones: milestones, on: selectedDate)
        let rows = items.map { AgendaRowFormatter.row($0, day: selectedDate, text: text, myUserId: myUserId) }
        guard !rows.isEmpty else { return (.empty, nil) }
        let marker = now.flatMap {
            AgendaNowRules.marker(items: items, now: $0, zone: zone.timeZone, day: selectedDate, text: text)
        }
        return (.content(rows), marker)
    }

    static func zoneNotice(zone: ScheduleZone, deviceZone: TimeZone, text: ScheduleText) -> String? {
        guard ZoneNotice.make(zone: zone, deviceZone: deviceZone) != nil else { return nil }
        return zone.isFallback
            ? ScheduleStrings.format("schedule.zone.fallback", text.zoneName())
            : ScheduleStrings.format("schedule.zone.notice", text.zoneName())
    }

    static func cellLabel(
        _ date: CalendarDate,
        today: CalendarDate,
        inPeriod: Bool,
        marker: DayMarker,
        text: ScheduleText
    ) -> String {
        var parts = [text.fullDay(date)]
        if date == today { parts.append(ScheduleStrings.text("schedule.cell.today")) }
        if marker.events > 0 { parts.append(ScheduleStrings.count("schedule.cell.events", marker.events)) }
        if marker.celebrations > 0 {
            parts.append(ScheduleStrings.count("schedule.cell.celebrations", marker.celebrations))
        }
        if !inPeriod { parts.append(ScheduleStrings.text("schedule.cell.outside")) }
        return parts.joined(separator: ScheduleStrings.text("schedule.list.separator"))
    }
}

/// Formats one agenda item (07 §3 card copy).
enum AgendaRowFormatter {
    static func row(_ item: AgendaItem, day: CalendarDate, text: ScheduleText, myUserId: String? = nil) -> AgendaRow {
        var row = baseRow(item, day: day, text: text, myUserId: myUserId)
        row.rail = rail(item, text: text)
        return row
    }

    /// The Day rail: celebrations, holidays and all-day items read "All day"; an item that began
    /// the day before reads "Until" its end; anything else its start.
    static func rail(_ item: AgendaItem, text: ScheduleText) -> AgendaRail {
        let timing: EventTiming? =
            switch item {
            case .event(_, let timing), .timeOff(_, let timing): timing
            case .celebration, .holiday: nil
            }
        guard case .timed(let start, let end, let startsBefore, _) = timing else {
            return AgendaRail(time: ScheduleStrings.text("schedule.allDay"), kicker: nil)
        }
        if startsBefore, end > start {
            return AgendaRail(time: text.clock(end), kicker: ScheduleStrings.text("schedule.untilKicker"))
        }
        return AgendaRail(time: text.clock(start), kicker: nil)
    }

    private static func celebrationRow(_ celebration: ScheduleCelebration, id: String, myUserId: String?) -> AgendaRow {
        let copy = CelebrationText(celebration)
        var row = AgendaRow(
            id: id,
            kind: .celebration(celebration),
            title: copy.full,
            subtitle: CelebrationText.kindLabel(celebration),
            accessibilityLabel: copy.accessible
        )
        row.emoji = CelebrationText.emoji(celebration)
        row.isMine = myUserId != nil && celebration.userId == myUserId
        if row.isMine {
            // Your own card speaks to you; it has no Send wishes either.
            let sentence = CelebrationText.selfSentence(celebration)
            row.title = sentence
            row.accessibilityLabel = sentence
        }
        return row
    }

    private static func baseRow(
        _ item: AgendaItem,
        day: CalendarDate,
        text: ScheduleText,
        myUserId: String?
    ) -> AgendaRow {
        switch item {
        case .celebration(let celebration):
            return celebrationRow(celebration, id: item.id, myUserId: myUserId)
        case .holiday(let holiday):
            let title = holiday.title ?? ScheduleStrings.text("schedule.holiday.default")
            let subtitle = holiday.details ?? ScheduleStrings.text("schedule.holiday.subtitle")
            return AgendaRow(
                id: item.id,
                kind: .holiday,
                title: title,
                subtitle: subtitle,
                accessibilityLabel: label(title, subtitle)
            )
        case .timeOff(let entry, _):
            let title = entry.leaveType ?? ScheduleStrings.text("schedule.timeOff.default")
            let subtitle = timeOffSubtitle(entry)
            return AgendaRow(
                id: item.id,
                kind: .timeOff,
                title: title,
                subtitle: subtitle,
                accessibilityLabel: label(title, subtitle)
            )
        case .event(let event, let timing):
            let title = event.title ?? ScheduleStrings.untitledEvent
            let when = timingText(timing, day: day, text: text)
            let subtitle = event.location.map { ScheduleStrings.format("schedule.withDetail", when, $0) } ?? when
            let owner = ScheduleCopy.nonBlank(event.ownerName).map { ScheduleStrings.format("schedule.owner", $0) }
            var row = AgendaRow(
                id: item.id,
                kind: .event(id: event.id),
                title: title,
                subtitle: subtitle,
                accessibilityLabel: label(title, [subtitle, owner].compactMap { $0 }.joined(separator: ", ")),
                ownerColor: ScheduleCopy.ownerColor(event.ownerColor)
            )
            row.owner = owner
            row.isOnline = event.isOnline
            return row
        }
    }

    /// "Approved · half day am" (07 §3).
    static func timeOffSubtitle(_ entry: CalendarTimeOff) -> String {
        let type = ScheduleCopy.requestTypeLabel(entry.requestType)
        guard let status = ScheduleCopy.sentenceCase(entry.status) else { return type }
        return ScheduleStrings.format("schedule.withDetail", status, type)
    }

    /// "10:00 PM – 11:00 PM"; ends on another day carry their weekday ("Sat 10:00 PM – Sun 1:00 AM").
    static func timingText(_ timing: EventTiming, day: CalendarDate, text: ScheduleText) -> String {
        switch timing {
        case .allDay:
            return ScheduleStrings.text("schedule.allDay")
        case .timed(let start, let end, let startsBefore, let endsAfter):
            let zone = text.zone
            let startText =
                startsBefore
                ? ScheduleStrings.format(
                    "schedule.dayTime",
                    text.weekdayShort(CalendarDate(start, in: zone)),
                    text.clock(start)
                )
                : text.clock(start)
            guard end > start else { return startText }
            let endText =
                endsAfter
                ? ScheduleStrings.format(
                    "schedule.dayTime",
                    text.weekdayShort(CalendarDate(end, in: zone)),
                    text.clock(end)
                )
                : text.clock(end)
            return ScheduleStrings.format("schedule.range", startText, endText)
        }
    }

    private static func label(_ title: String, _ subtitle: String) -> String {
        [title, subtitle].joined(separator: ScheduleStrings.text("schedule.list.separator"))
    }
}

/// Where "now" falls in today's agenda (UI4-12). Everything compares instants, so a fall-back
/// day's repeated hour cannot misplace the line.
enum AgendaNowRules {
    static func marker(
        items: [AgendaItem],
        now: Date,
        zone: TimeZone,
        day: CalendarDate,
        text: ScheduleText
    ) -> AgendaNowMarker? {
        guard CalendarDate(now, in: zone) == day else { return nil }
        let timed = items.compactMap { item in endsAt(item).map { (item.id, $0) } }
        guard !timed.isEmpty else { return nil }
        // An item with no length is a moment: it has ended once its start has passed.
        let ended = Set(timed.filter { $0.1 <= now }.map(\.0))
        let firstOpen = timed.first { $0.1 > now }?.0
        return AgendaNowMarker(time: text.clock(now), beforeID: firstOpen, endedIDs: ended)
    }

    /// When a timed item ends; nil for all-day items, celebrations and holidays, which never end
    /// during the day.
    private static func endsAt(_ item: AgendaItem) -> Date? {
        switch item {
        case .event(_, .timed(let start, let end, _, _)), .timeOff(_, .timed(let start, let end, _, _)):
            max(start, end)
        default:
            nil
        }
    }
}
