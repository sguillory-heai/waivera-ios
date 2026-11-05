import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Something the form itself can see is wrong, worded like sprout_web's `localSelectionIssue`.
public enum LeaveIssue: Sendable, Hashable { case endBeforeStart, tooShort, tooLong }

/// The server's look at the dates: hours, balance and anything that blocks them.
public enum LeaveCheck: Sendable, Hashable {
    /// Not enough filled in yet, or the form already shows an issue.
    case idle
    case checking
    case ready(LeavePreview)
    case failed
}

public enum LeaveTypesState: Sendable, Hashable {
    case loading
    case failed
    case ready([LeaveType])
}

/// A refused send; a nil `problem` gets the general wording.
public struct SendFailure: Sendable, Hashable {
    public var problem: LeaveSendProblem?
}

/// The Request time off form (Android `TimeOffFormState`): sprout_web `AdminRequestModal`'s
/// fields and local checks. Times are minutes after midnight in the person's saved zone.
public struct TimeOffFormState: Sendable, Hashable {
    public var types: LeaveTypesState = .loading
    public var typeId: Int?
    public var partialDay = false
    public var firstDay: CalendarDate?
    public var lastDay: CalendarDate?
    public var day: CalendarDate?
    public var from: Int?
    public var to: Int?
    public var note = ""
    public var issue: LeaveIssue?
    public var check: LeaveCheck = .idle
    /// The first day is before today in the person's zone: allowed, with the web's note.
    public var past = false
    public var sending = false
    /// The last send's refusal, shown until the person changes something or sends again.
    public var failure: SendFailure?
    public var today: CalendarDate

    public init(today: CalendarDate) { self.today = today }

    public var type: LeaveType? {
        guard case .ready(let list) = types else { return nil }
        return list.first { $0.id == typeId }
    }

    var preview: LeavePreview? {
        if case .ready(let preview) = check { return preview }
        return nil
    }

    /// A balance-keeping type that this request would take below zero; the server refuses it.
    public var overBalance: Bool {
        guard let preview else { return false }
        return preview.tracksBalance && (preview.afterMinutes ?? 0) < 0
    }

    public var canSend: Bool {
        !sending && issue == nil && preview != nil && preview?.block == nil && !overBalance
    }
}

/// Turns the form into what the server is sent, and the checks the form makes on its own.
enum TimeOffDrafts {
    static let minPartialMinutes = 30
    static let maxPartialMinutes = 480

    static func draft(_ state: TimeOffFormState, zone: TimeZone) -> LeaveDraft? {
        guard let typeId = state.typeId, let start = start(state, zone: zone), let end = end(state, zone: zone)
        else { return nil }
        let note = state.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return LeaveDraft(
            leaveTypeId: typeId,
            partialDay: state.partialDay,
            start: start,
            end: end,
            note: note.isEmpty ? nil : note
        )
    }

    // sprout_web sends calendar days as UTC bounds (T00:00:00.000Z to T23:59:59.999Z) and partial
    // days as instants; partial days are read in the employee's saved zone.
    private static func start(_ state: TimeOffFormState, zone: TimeZone) -> Date? {
        if state.partialDay {
            guard let day = state.day, let from = state.from else { return nil }
            return instant(day, minutes: from, zone: zone)
        }
        return state.firstDay.map(utcMidnight)
    }

    private static func end(_ state: TimeOffFormState, zone: TimeZone) -> Date? {
        if state.partialDay {
            guard let day = state.day, let to = state.to else { return nil }
            return instant(day, minutes: to, zone: zone)
        }
        return state.lastDay.map { utcMidnight($0.adding(days: 1)).addingTimeInterval(-0.001) }
    }

    static func utcMidnight(_ day: CalendarDate) -> Date {
        Date(timeIntervalSince1970: Double(day.daysSinceEpoch) * 86_400)
    }

    /// The wall-clock time on `day` in `zone`; a time skipped by a DST change moves forward.
    static func instant(_ day: CalendarDate, minutes: Int, zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = DateComponents(
            year: day.year,
            month: day.month,
            day: day.day,
            hour: minutes / 60,
            minute: minutes % 60
        )
        return calendar.date(from: parts)
    }

    static func issue(_ state: TimeOffFormState, zone: TimeZone) -> LeaveIssue? {
        if state.partialDay {
            guard let start = start(state, zone: zone), let end = end(state, zone: zone) else { return nil }
            let minutes = Int(end.timeIntervalSince(start) / 60)
            if minutes < minPartialMinutes { return .tooShort }
            if minutes > maxPartialMinutes { return .tooLong }
            return nil
        }
        if let first = state.firstDay, let last = state.lastDay, last < first { return .endBeforeStart }
        return nil
    }

    static func past(_ state: TimeOffFormState, today: CalendarDate) -> Bool {
        guard let first = state.partialDay ? state.day : state.firstDay else { return false }
        return first < today
    }

    /// Stands in on the profile until it reloads the real request.
    static func pending(_ state: TimeOffFormState) -> TimeOffEntry {
        TimeOffEntry(
            id: TimeOffFormModel.pendingId,
            leaveType: state.type?.name,
            start: state.partialDay ? state.day : state.firstDay,
            end: state.partialDay ? state.day : state.lastDay,
            status: .pending
        )
    }
}

/// The Request time off form (Android `TimeOffFormViewModel`). The profile keeps one, so a send
/// that finishes after the sheet closes still shows the pending request. The server's check
/// runs 250 ms after a change; fields freeze while a send is out.
@MainActor
@Observable
public final class TimeOffFormModel {
    public static let noteMaxLength = 1_000
    static let pendingId = -1
    private static let checkDelay: Duration = .milliseconds(250)

    public private(set) var state: TimeOffFormState

    @ObservationIgnored private let requests: any RequestsRepository
    @ObservationIgnored private let calendar: any CalendarRepository
    @ObservationIgnored private let clock: any WaiveraClock
    @ObservationIgnored private var checking: Task<Void, Never>?
    @ObservationIgnored private var loadingTypes: Task<Void, Never>?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    /// Told when a send went through, with the request to show as pending.
    @ObservationIgnored public var onSent: ((TimeOffEntry) -> Void)?

    public init(requests: any RequestsRepository, calendar: any CalendarRepository, clock: any WaiveraClock) {
        self.requests = requests
        self.calendar = calendar
        self.clock = clock
        let zone = calendar.scheduleTimeZone().zone
        state = TimeOffFormState(today: CalendarDate(clock.now, in: zone))
    }

    public convenience init(environment: DataEnvironment) {
        self.init(requests: environment.requests, calendar: environment.calendar, clock: environment.clock)
    }

    /// The person's saved zone: partial days and "today" are read in it.
    var zone: TimeZone { calendar.scheduleTimeZone().zone }

    /// Starts an empty form, like the web's modal on every open, and loads the leave types the
    /// first time. A send still in flight is kept, so closing the sheet mid-send never loses its
    /// result.
    public func reset() {
        guard !state.sending else { return }
        checking?.cancel()
        let types = state.types
        state = TimeOffFormState(today: CalendarDate(clock.now, in: zone))
        state.types = types
        if case .ready = types { return }
        loadTypes()
    }

    public func loadTypes() {
        state.types = .loading
        loadingTypes?.cancel()
        let requests = requests
        loadingTypes = Task { [weak self] in
            let types = try? await requests.leaveTypes()
            guard let self, !Task.isCancelled else { return }
            self.state.types = types.map(LeaveTypesState.ready) ?? .failed
        }
    }

    public func pickType(_ id: Int) { change { $0.typeId = id } }

    public func setPartialDay(_ partial: Bool) { change { $0.partialDay = partial } }

    public func pickFirstDay(_ day: CalendarDate) {
        change { form in
            // A first day after the last moves the last day with it, so the range never reads backwards.
            if let last = form.lastDay, last >= day {
                form.lastDay = last
            } else {
                form.lastDay = day
            }
            form.firstDay = day
        }
    }

    public func pickLastDay(_ day: CalendarDate) { change { $0.lastDay = day } }

    public func pickDay(_ day: CalendarDate) { change { $0.day = day } }

    public func pickFrom(_ minutes: Int) { change { $0.from = minutes } }

    public func pickTo(_ minutes: Int) { change { $0.to = minutes } }

    public func setNote(_ text: String) {
        guard !state.sending else { return }
        state.note = String(text.prefix(Self.noteMaxLength))
        state.failure = nil
    }

    public func retryCheck() { change { _ in } }

    public func send() {
        guard state.canSend, let draft = TimeOffDrafts.draft(state, zone: zone) else { return }
        let sent = state
        state.sending = true
        state.failure = nil
        let requests = requests
        sendTask = Task { [weak self] in
            do {
                try await requests.requestTimeOff(draft)
                guard let self else { return }
                self.state.sending = false
                self.onSent?(TimeOffDrafts.pending(sent))
            } catch {
                guard let self else { return }
                self.state.sending = false
                self.state.failure = SendFailure(problem: (error as? LeaveSendError)?.problem)
            }
        }
    }

    /// Applies `edit`, re-runs the local checks, then asks the server again after a short pause.
    private func change(_ edit: (inout TimeOffFormState) -> Void) {
        // The fields are frozen while a send is out, so what was sent is what the form shows.
        guard !state.sending else { return }
        let zone = zone
        let today = CalendarDate(clock.now, in: zone)
        var next = state
        edit(&next)
        next.issue = TimeOffDrafts.issue(next, zone: zone)
        next.past = TimeOffDrafts.past(next, today: today)
        next.today = today
        next.check = .idle
        next.failure = nil
        checking?.cancel()
        guard next.issue == nil, let draft = TimeOffDrafts.draft(next, zone: zone) else {
            state = next
            return
        }
        next.check = .checking
        state = next
        let requests = requests
        checking = Task { [weak self] in
            try? await Task.sleep(for: Self.checkDelay)
            guard !Task.isCancelled else { return }
            let preview = try? await requests.previewLeave(draft)
            guard let self, !Task.isCancelled else { return }
            self.state.check = preview.map(LeaveCheck.ready) ?? .failed
        }
    }
}
