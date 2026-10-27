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
                inPeriod: inPeriod,
                isToday: date == today,
                isSelected: date == selectedDate,
                marker: marker,
                accessibilityLabel: Self.cellLabel(date, today: today, inPeriod: inPeriod, marker: marker, text: text)
            )
        }
        return ScheduleUIState(
            view: view,
            selectedDate: selectedDate,
            today: today,
            zoneIdentifier: zone.identifier,
            zoneNotice: Self.zoneNotice(zone: zone, deviceZone: deviceZone, text: text),
            title: text.title(SchedulePeriods.title(view, for: selectedDate)),
            weekdayHeaders: text.weekdayHeaders,
            cells: cells,
            agendaHeading: text.fullDay(selectedDate),
            agenda: agenda(feedValue, text: text),
            isRefreshing: feed?.isRefreshing ?? false,
            feedNotice: feedNotice,
            milestonesFailed: milestonesFailed
        )
    }

    private var feedNotice: String? {
        guard let feed, feed.value != nil, feed.error != nil else { return nil }
        return ScheduleStrings.text(isOffline ? "schedule.offline" : "schedule.refreshFailed")
    }

    private func agenda(_ value: CalendarFeed, text: ScheduleText) -> AgendaState {
        guard let feed else { return .loading }
        if feed.value == nil {
            if let error = feed.error { return .error(error) }
            return .loading
        }
        let items = ScheduleAgenda.items(feed: value, zone: zone.timeZone, milestones: milestones, on: selectedDate)
        let rows = items.map { AgendaRowFormatter.row($0, day: selectedDate, text: text) }
        return rows.isEmpty ? .empty : .content(rows)
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
    static func row(_ item: AgendaItem, day: CalendarDate, text: ScheduleText) -> AgendaRow {
        switch item {
        case .celebration(let celebration):
            let copy = CelebrationText(celebration)
            return AgendaRow(
                id: item.id,
                kind: .celebration(celebration),
                title: copy.full,
                subtitle: CelebrationText.kindLabel(celebration),
                accessibilityLabel: copy.accessible
            )
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
            return AgendaRow(
                id: item.id,
                kind: .event(id: event.id),
                title: title,
                subtitle: subtitle,
                accessibilityLabel: label(title, subtitle),
                ownerColor: ScheduleCopy.ownerColor(event.ownerColor)
            )
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
