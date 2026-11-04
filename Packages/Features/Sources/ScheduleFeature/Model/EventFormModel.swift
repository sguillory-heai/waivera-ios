import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// The quick event form's screen state. Times are wall-clock minutes in the employee's saved zone.
public struct EventFormState: Sendable, Hashable {
    public var isEdit = false
    public var title = ""
    public var date: CalendarDate
    public var startMinute = EventFormModel.defaultHour * 60
    public var endMinute = EventFormModel.defaultHour * 60 + EventFormModel.defaultLength
    public var allDay = false
    public var waiveraVideo = true
    public var location = ""
    public var notes = ""
    public var zone: TimeZone
    public var invitees: [AttendeeOption] = []
    /// Email the invited participants; only offered once a participant is invited.
    public var notifyParticipants = false
    public var query = ""
    /// People matching `query` who are not invited yet; empty until the person types.
    public var matches: [AttendeeOption] = []
    public var directoryFailed = false
    public var showErrors = false
    public var isSaving = false
    public var saveFailed = false

    public var titleMissing: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var endBeforeStart: Bool { !allDay && endMinute <= startMinute }
    public var isValid: Bool { !titleMissing && !endBeforeStart }
    public var hasParticipants: Bool { invitees.contains { $0.isParticipant } }
    public var coworkers: [AttendeeOption] { invitees.filter { !$0.isParticipant } }
    public var participants: [AttendeeOption] { invitees.filter(\.isParticipant) }

    /// The instants the pickers bind to; shown in `zone` by the view.
    public var dayInstant: Date { date.instant(atMinute: 12 * 60, in: zone) }
    public var startInstant: Date { date.instant(atMinute: startMinute, in: zone) }
    public var endInstant: Date { date.instant(atMinute: endMinute, in: zone) }

    /// "Wed, Nov 4, 2026", "9:00 AM": the pickers' values in the saved zone, in Android's
    /// patterns (times are always 12-hour).
    public var dayText: String { Self.text(dayInstant, pattern: "EEE, MMM d, yyyy", zone: zone) }
    public var startText: String { Self.text(startInstant, pattern: "h:mm a", zone: zone) }
    public var endText: String { Self.text(endInstant, pattern: "h:mm a", zone: zone) }

    static func text(_ instant: Date, pattern: String, zone: TimeZone, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: instant)
    }

    public var zoneNote: String {
        let name = zone.localizedName(for: .generic, locale: .current) ?? zone.identifier
        return ScheduleStrings.format("schedule.form.zoneNote", name)
    }

    public var notifyNote: String {
        ScheduleStrings.text(isEdit ? "schedule.form.notify.edit" : "schedule.form.notify.note")
    }
}

/// A finished save, for the view to close the sheet and say "Event created" or "Event saved".
public struct EventSaved: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let created: Bool

    public var message: String { ScheduleStrings.text(created ? "schedule.form.created" : "schedule.form.saved") }
}

/// The quick event form: create, or edit your own one-off event (Android `EventFormViewModel`).
@MainActor
@Observable
public final class EventFormModel {
    nonisolated static let defaultHour = 9
    nonisolated static let defaultLength = 30
    static let lastDefaultHour = 23
    static let maxMatches = 6
    static let maxTitle = 200
    static let maxLocation = 500
    static let maxNotes = 4_000
    static let lastMinute = 23 * 60 + 59

    public private(set) var state: EventFormState
    public private(set) var saved: EventSaved?

    @ObservationIgnored private var directory: [AttendeeOption] = []
    @ObservationIgnored private let editing: CalendarEvent?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    private let calendar: any CalendarRepository
    private let webBaseURL: URL?

    /// `event` edits it; otherwise a new event on `date` (today when nil).
    public init(
        event: CalendarEvent? = nil,
        date: CalendarDate? = nil,
        calendar: any CalendarRepository,
        clock: any WaiveraClock,
        webBaseURL: URL? = nil
    ) {
        self.calendar = calendar
        self.webBaseURL = webBaseURL
        editing = event
        let zone = calendar.scheduleTimeZone().zone
        let now = clock.now
        let today = CalendarDate(now, in: zone)
        if let event {
            state = Self.editState(event, zone: zone, today: today)
        } else {
            var form = EventFormState(date: date ?? today, zone: zone)
            let minute = CalendarDate.minuteOfDay(now, in: zone)
            if form.date == today, minute / 60 < Self.lastDefaultHour {
                form.startMinute = (minute / Self.defaultLength + 1) * Self.defaultLength
            }
            form.endMinute = min(form.startMinute + Self.defaultLength, Self.lastMinute)
            state = form
        }
    }

    public convenience init(event: CalendarEvent? = nil, date: CalendarDate? = nil, data: DataEnvironment) {
        self.init(event: event, date: date, calendar: data.calendar, clock: data.clock, webBaseURL: data.webBaseURL)
    }

    private static func editState(_ event: CalendarEvent, zone: TimeZone, today: CalendarDate) -> EventFormState {
        var form = EventFormState(date: event.allDay?.start ?? CalendarDate(event.start, in: zone), zone: zone)
        form.isEdit = true
        form.title = event.title ?? ""
        form.allDay = event.isAllDay
        if !event.isAllDay {
            form.startMinute = CalendarDate.minuteOfDay(event.start, in: zone)
            form.endMinute = CalendarDate.minuteOfDay(event.end, in: zone)
        }
        form.waiveraVideo = !event.isSprout
        form.location = event.isSprout ? (event.location ?? "") : ""
        form.notes = event.details ?? ""
        let invited = Set(EventPayload.invitees(event))
        let participants = Set(EventPayload.participants(event))
        var seen = Set<String>()
        form.invitees = event.attendees.compactMap { attendee -> AttendeeOption? in
            guard let ref = attendee.ref else { return nil }
            let participant = attendee.kind == .waiverParticipant && participants.contains(ref)
            let coworker = attendee.kind == .employee && invited.contains(ref)
            guard participant || coworker else { return nil }
            return AttendeeOption(
                id: ref,
                name: attendee.displayName ?? attendee.email ?? "",
                email: attendee.email,
                isParticipant: participant
            )
        }
        .filter { seen.insert($0.key).inserted }
        return form
    }

    /// Loads the invite directory; the view runs it in its task and Retry runs it again.
    public func loadDirectory() async {
        do {
            directory = try await calendar.attendeeOptions(eventId: editing?.id)
            state.directoryFailed = false
        } catch {
            state.directoryFailed = true
        }
        state.matches = matches(for: state)
    }

    // MARK: Fields

    public func setTitle(_ text: String) { edit { $0.title = String(text.prefix(Self.maxTitle)) } }
    public func setAllDay(_ allDay: Bool) { edit { $0.allDay = allDay } }
    public func setDate(_ instant: Date) { edit { $0.date = CalendarDate(instant, in: $0.zone) } }

    /// Moving the start keeps the event's length, as calendars do.
    public func setStart(_ instant: Date) {
        edit { form in
            let start = CalendarDate.minuteOfDay(instant, in: form.zone)
            let length = form.endMinute > form.startMinute ? form.endMinute - form.startMinute : Self.defaultLength
            form.startMinute = start
            form.endMinute = min(start + length, Self.lastMinute)
        }
    }

    public func setEnd(_ instant: Date) { edit { $0.endMinute = CalendarDate.minuteOfDay(instant, in: $0.zone) } }
    public func setVideo(_ video: Bool) { edit { $0.waiveraVideo = video } }
    public func setLocation(_ text: String) { edit { $0.location = String(text.prefix(Self.maxLocation)) } }
    public func setNotes(_ text: String) { edit { $0.notes = String(text.prefix(Self.maxNotes)) } }

    public func setQuery(_ text: String) {
        state.query = text
        state.matches = matches(for: state)
    }

    public func invite(_ person: AttendeeOption) {
        edit { form in
            guard !form.invitees.contains(where: { $0.key == person.key }) else { return }
            form.invitees.append(person)
            form.query = ""
        }
    }

    public func uninvite(_ person: AttendeeOption) { edit { $0.invitees.removeAll { $0.key == person.key } } }
    public func setNotifyParticipants(_ notify: Bool) { edit { $0.notifyParticipants = notify } }

    // MARK: Save

    public func save() {
        guard !state.isSaving else { return }
        guard state.isValid else {
            state.showErrors = true
            return
        }
        state.isSaving = true
        state.saveFailed = false
        let form = state
        let draft = EventDraft(
            title: form.title,
            date: form.date,
            startMinute: form.startMinute,
            endMinute: form.endMinute,
            allDay: form.allDay,
            inviteeIds: form.coworkers.map(\.id),
            participantIds: form.participants.map(\.id),
            notifyParticipants: form.notifyParticipants && form.hasParticipants,
            waiveraVideo: form.waiveraVideo,
            location: form.waiveraVideo ? nil : form.location,
            description: form.notes
        )
        let calendar = calendar
        let editing = editing
        saveTask?.cancel()
        saveTask = Task {
            do {
                if let editing {
                    try await calendar.updateEvent(editing, with: draft)
                } else {
                    try await calendar.createEvent(draft)
                }
                self.finishSave(failed: false)
            } catch {
                self.finishSave(failed: true)
            }
        }
    }

    /// "More options on the web": recurrence and linked tasks live in the web calendar.
    public var webCalendarURL: URL? { WebAddress.page(CalendarEventModel.webCalendarPath, on: webBaseURL) }

    private func finishSave(failed: Bool) {
        state.isSaving = false
        if failed {
            state.saveFailed = true
        } else {
            saved = EventSaved(id: UUID(), created: editing == nil)
        }
    }

    /// Field edits are ignored while saving and clear a stale save failure.
    private func edit(_ change: (inout EventFormState) -> Void) {
        guard !state.isSaving else { return }
        var form = state
        change(&form)
        form.saveFailed = false
        form.matches = matches(for: form)
        state = form
    }

    private func matches(for form: EventFormState) -> [AttendeeOption] {
        let query = form.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let invited = Set(form.invitees.map(\.key))
        return Array(
            directory.lazy
                .filter { !invited.contains($0.key) }
                .filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                        || ($0.email?.localizedCaseInsensitiveContains(query) ?? false)
                }
                .prefix(Self.maxMatches)
        )
    }
}

extension EventFormModel: Identifiable {}
