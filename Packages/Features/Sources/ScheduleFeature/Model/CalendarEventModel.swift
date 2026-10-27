import Foundation
import Observation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// Event detail (07 §7). Accept and Decline are optimistic: the answer shows at once with Undo,
/// nothing is sent until the undo toast goes away (or the safety timer runs out), and a failed
/// save rolls back with a visible Retry. An answer still in its undo window when the screen goes
/// away is sent anyway: it is the person's decision.
///
/// Opened by id from the schedule, Today, a push or a deep link. The repository's single-event
/// lookup serves it from the cache and fetches it when the id is cold.
@MainActor
@Observable
public final class CalendarEventModel {
    public let eventID: String
    public internal(set) var state: EventUIState = .loading
    public private(set) var undoOffer: UndoOffer?
    public internal(set) var openRequest: OpenRequest?
    public internal(set) var conversationRequest: ConversationRequest?
    /// Haptic triggers: each increments once per moment (choice, saved, failure).
    public private(set) var choiceTicks = 0
    public private(set) var successTicks = 0
    public internal(set) var failureTicks = 0
    /// The safety net for committing an answer; the toast's own dismissal normally commits first.
    @ObservationIgnored public var undoWindow: Duration = .seconds(FeedbackTiming.undoToastAccessible)

    private var lookup: Resource<EventLookup>?
    var interaction = EventInteraction()
    private var now: Date
    private var zone: ScheduleZone
    private var myUserId: String?
    @ObservationIgnored private var milestones = MilestoneCalendar.empty
    @ObservationIgnored private var milestoneValue: MilestoneIndex?
    @ObservationIgnored private var text: ScheduleText
    @ObservationIgnored private var token = 0
    @ObservationIgnored var found: CalendarEvent?
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored var joinTask: Task<Void, Never>?
    @ObservationIgnored var chatTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    let calendar: any CalendarRepository
    let conversations: any ConversationsRepository
    private let session: any SessionRepository
    private let clock: any WaiveraClock
    private let deviceZone: @Sendable () -> TimeZone
    private let locale: Locale

    public init(
        eventID: String,
        calendar: any CalendarRepository,
        conversations: any ConversationsRepository,
        session: any SessionRepository,
        clock: any WaiveraClock = SystemClock(),
        deviceZone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        locale: Locale = .autoupdatingCurrent
    ) {
        self.eventID = eventID
        self.calendar = calendar
        self.conversations = conversations
        self.session = session
        self.clock = clock
        self.deviceZone = deviceZone
        self.locale = locale
        let user = session.currentState.user
        let zone = ScheduleZone.resolve(savedIdentifier: user?.timeZoneIdentifier)
        self.zone = zone
        myUserId = user?.id
        now = clock.now
        text = ScheduleText(zone: zone.timeZone, locale: locale)
    }

    public convenience init(eventID: String, data: DataEnvironment) {
        self.init(
            eventID: eventID,
            calendar: data.calendar,
            conversations: data.conversations,
            session: data.session,
            clock: data.clock
        )
    }

    // MARK: Lifecycle

    /// Watches the event and milestones; fetches the event when nothing is cached. Runs until
    /// the view's task is cancelled.
    public func observe() async {
        let calendar = calendar
        let eventID = eventID
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await resource in calendar.milestones() { await self.apply(milestones: resource) }
            }
            group.addTask {
                var checked = false
                for await resource in calendar.event(id: eventID) {
                    await self.apply(lookup: resource)
                    if !checked {
                        checked = true
                        if resource.phase != .loading, resource.value == nil || resource.updatedAt == nil {
                            await calendar.refreshEvent(id: eventID)
                        }
                    }
                }
            }
        }
    }

    /// Keeps the join window and the buttons current; the view calls it on a timer and on resume.
    public func tick() {
        now = clock.now
        rebuild()
    }

    /// The error state's Retry: refetch the event.
    public func retry() {
        refreshTask?.cancel()
        let calendar = calendar
        let eventID = eventID
        refreshTask = Task { await calendar.refreshEvent(id: eventID) }
    }

    /// The screen went away: an answer still in its undo window is sent now.
    public func disappear() {
        guard let pending = interaction.optimistic, pending.phase == .undoWindow else { return }
        commitTask?.cancel()
        commitTask = Task { await self.commit(pending.accept) }
    }

    // MARK: Invitation

    /// Accept (true) or Decline (false). Shows at once; nothing is sent until the undo window ends.
    public func respond(accept: Bool) {
        guard case .loaded(let details) = state, let invitation = details.invitation, invitation.canChange,
            invitation.phase != .saving
        else { return }
        let target: InvitationState = accept ? .accepted : .declined
        guard invitation.response != target else { return }
        commitTask?.cancel()
        interaction.failure = nil
        interaction.optimistic = OptimisticResponse(accept: accept, phase: .undoWindow)
        token += 1
        undoOffer = UndoOffer(
            id: UUID(),
            token: token,
            accept: accept,
            message: ScheduleStrings.text(accept ? "schedule.undo.accepted" : "schedule.undo.declined")
        )
        choiceTicks += 1
        let window = undoWindow
        let clock = clock
        let current = token
        commitTask = Task {
            do {
                try await clock.sleep(for: window)
            } catch {
                return
            }
            await self.commitIfPending(token: current)
        }
        rebuild()
    }

    /// Undo tapped: the answer was never sent, so the server's answer shows again.
    public func undo(_ offer: UndoOffer) {
        guard offer.token == token, interaction.optimistic?.phase == .undoWindow else { return }
        commitTask?.cancel()
        commitTask = nil
        interaction.optimistic = nil
        undoOffer = nil
        rebuild()
    }

    /// The toast went away without Undo: send now rather than waiting out the timer.
    public func undoDismissed(_ offer: UndoOffer) {
        guard offer.token == token else { return }
        if undoOffer?.token == offer.token { undoOffer = nil }
        guard let pending = interaction.optimistic, pending.phase == .undoWindow else { return }
        commitTask?.cancel()
        commitTask = Task { await self.commit(pending.accept) }
    }

    /// Retry after a failed save sends the same answer again.
    public func retryResponse() {
        guard let failed = interaction.failure else { return }
        interaction.failure = nil
        commitTask?.cancel()
        commitTask = Task { await self.commit(failed.accept) }
    }

    private func commitIfPending(token current: Int) async {
        guard current == token, let pending = interaction.optimistic, pending.phase == .undoWindow else { return }
        await commit(pending.accept)
    }

    private func commit(_ accept: Bool) async {
        interaction.optimistic = OptimisticResponse(accept: accept, phase: .saving)
        undoOffer = nil
        rebuild()
        do {
            try await calendar.respond(toEventId: eventID, accept: accept)
            interaction.optimistic = OptimisticResponse(accept: accept, phase: .saved)
            successTicks += 1
            rebuild()
            // The server is the source of truth: refetch so this screen shows its answer.
            await calendar.refreshEvent(id: eventID)
        } catch {
            interaction.optimistic = nil
            interaction.failure = ResponseFailure(accept: accept, error: WaiveraError.from(error))
            failureTicks += 1
            rebuild()
        }
    }

    // MARK: State

    private func apply(lookup resource: Resource<EventLookup>) {
        lookup = resource
        rebuild()
    }

    private func apply(milestones resource: Resource<MilestoneIndex>) {
        guard let index = resource.value, index != milestoneValue else { return }
        milestoneValue = index
        milestones = MilestoneCalendar(index)
        rebuild()
    }

    func rebuild() {
        switch lookupResult() {
        case .found(let event, let refreshFailed):
            found = event
            if let optimistic = interaction.optimistic, optimistic.phase == .saved,
                event.viewerResponse == (optimistic.accept ? .accepted : .declined)
            {
                interaction.optimistic = nil
            }
            let formatter = EventDetailsFormatter(
                zone: zone,
                deviceZone: deviceZone(),
                now: now,
                myUserId: myUserId,
                milestones: milestones
            )
            state = .loaded(
                formatter.details(event, interaction: interaction, refreshFailed: refreshFailed, text: text)
            )
        case .loading:
            if found == nil { state = .loading }
        case .failed(let error):
            state = .error(error)
        case .notFound:
            state = .notFound
        }
    }

    private enum Lookup {
        case loading
        case found(CalendarEvent, refreshFailed: Bool)
        case failed(WaiveraError)
        case notFound
    }

    private func lookupResult() -> Lookup {
        guard let lookup else { return .loading }
        switch lookup.value {
        case .found(let event): return .found(event, refreshFailed: lookup.error != nil)
        case .notFound: return lookup.error.map(Lookup.failed) ?? .notFound
        case nil: return lookup.error.map(Lookup.failed) ?? .loading
        }
    }
}
