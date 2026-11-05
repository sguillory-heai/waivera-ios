import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// How the plan (CPOC) year stands today, in the employee's saved zone.
enum PlanStatus: Hashable, Sendable {
    case endsIn(days: Int)
    case endsToday
    case endedAgo(days: Int)

    /// Days are counted on the calendar, so a daylight saving change never makes a day 23 or 25 hours.
    static func of(end: CalendarDate, today: CalendarDate) -> PlanStatus {
        let days = today.days(until: end)
        if days > 0 { return .endsIn(days: days) }
        return days == 0 ? .endsToday : .endedAgo(days: -days)
    }

    var ended: Bool { if case .endedAgo = self { true } else { false } }

    /// Day one has its own words, as on Android.
    var text: String {
        switch self {
        case .endsIn(let days) where days == 1: TasksStrings.text("tasks.participant.planEndsTomorrow")
        case .endsIn(let days): TasksStrings.plural("tasks.participant.planEndsIn", days)
        case .endsToday: TasksStrings.text("tasks.participant.planEndsToday")
        case .endedAgo(let days) where days == 1: TasksStrings.text("tasks.participant.planEndedYesterday")
        case .endedAgo(let days): TasksStrings.plural("tasks.participant.planEnded", days)
        }
    }
}

struct ParticipantScreenState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case loading, content, error, forbidden }

    var phase: Phase = .loading
    var profile: ParticipantProfile?
    var plan: PlanStatus?
    var tasks: Loadable<[TaskRow]> = .loading
    var overdue = 0
}

/// The read-only participant profile (web Participant Profile tab, Android
/// `ParticipantViewModel`) and their open tasks. Nothing here edits: changes and the rest of
/// the record stay on the web.
@MainActor
@Observable
final class ParticipantModel {
    private(set) var state = ParticipantScreenState()
    let feedback = TasksFeedback()

    @ObservationIgnored let participantId: Int
    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private let firstWeekday: Int
    @ObservationIgnored private let bag = TaskBag()
    @ObservationIgnored private var local = Local()

    private struct Local {
        var phase: ParticipantScreenState.Phase = .loading
        var profile: ParticipantProfile?
        var tasks: Loadable<[TaskSummary]> = .loading
    }

    init(participantId: Int, environment: DataEnvironment, firstWeekday: Int = Calendar.current.firstWeekday) {
        self.participantId = participantId
        self.environment = environment
        self.firstWeekday = firstWeekday
    }

    /// A retry replaces the load in flight, so an older answer never lands over a newer one.
    func load() {
        if local.profile == nil { local.phase = .loading }
        rebuild()
        let participants = environment.participants
        let id = participantId
        bag.replace("profile") { [weak self] in
            let result = await attempt { try await participants.profile(id: id) }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let profile):
                self.local.phase = .content
                self.local.profile = profile
                self.loadTasks()
            case .failure(let error):
                // A refresh that fails keeps what is on screen.
                if self.local.profile == nil {
                    self.local.phase = WaiveraError.from(error) == .forbidden ? .forbidden : .error
                }
            }
            self.rebuild()
        }
    }

    func loadTasks() {
        if local.tasks.value == nil { local.tasks = .loading }
        rebuild()
        let participants = environment.participants
        let id = participantId
        bag.replace("tasks") { [weak self] in
            let result = await attempt { try await participants.openTasks(id: id) }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let tasks): self.local.tasks = .ready(tasks)
            case .failure: if self.local.tasks.value == nil { self.local.tasks = .failed }
            }
            self.rebuild()
        }
    }

    /// The participant's snapshot on the web, or nil (with a note) when no web app is configured.
    func webURL() -> URL? {
        guard let url = TasksWeb.url("/participant/\(participantId)/participant-snapshot", base: environment.webBaseURL)
        else {
            feedback.show(TasksStrings.text("tasks.web.unavailable"))
            return nil
        }
        return url
    }

    /// `tel:` with the digits and a leading plus only, as Android dials.
    static func callURL(_ mobile: String) -> URL? {
        let digits = mobile.filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    static func mailURL(_ email: String) -> URL? {
        guard !email.contains(where: { $0.isWhitespace }), email.contains("@") else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        return components.url
    }

    private func rebuild() {
        let zone = environment.calendar.scheduleTimeZone().zone
        let today = CalendarDate(environment.clock.now, in: zone)
        let me = environment.session.currentState.user?.id
        let rows = local.tasks.map { tasks in
            tasks.map { TasksRules.row($0, today: today, me: me, firstWeekday: firstWeekday) }
        }
        state = ParticipantScreenState(
            phase: local.phase,
            profile: local.profile,
            plan: local.profile?.planEnd.map { PlanStatus.of(end: $0, today: today) },
            tasks: rows,
            overdue: rows.value?.filter { $0.daysLate != nil }.count ?? 0
        )
    }
}
