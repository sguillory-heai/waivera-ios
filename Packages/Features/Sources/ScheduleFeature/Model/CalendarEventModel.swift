import Foundation
import Observation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// A feed the event lookup watches.
struct LookupRange: Sendable, Hashable {
    var view: CalendarPeriod
    var anchor: CalendarDate
}

/// Event detail (07 §7). Accept and Decline are optimistic: the answer shows at once with Undo,
/// nothing is sent until the undo toast goes away (or the safety timer runs out), and a failed
/// save rolls back with a visible Retry. An answer still in its undo window when the screen goes
/// away is sent anyway: it is the person's decision.
///
/// Opened by id from the schedule, Today, a push or a deep link. `CalendarRepository` has no
/// single-event call (docs/requests/schedule.md §1), so the model watches the range the schedule
/// last saw the event in, or the month grids around today for a cold id.
@MainActor
@Observable
public final class CalendarEventModel {
    public let eventID: String
    public private(set) var state: EventUIState = .loading
    public private(set) var undoOffer: UndoOffer?
    public private(set) var openRequest: OpenRequest?
    public private(set) var conversationRequest: ConversationRequest?
    /// Haptic triggers: each increments once per moment (choice, saved, failure).
    public private(set) var choiceTicks = 0
    public private(set) var successTicks = 0
    public private(set) var failureTicks = 0
    /// The safety net for committing an answer; the toast's own dismissal normally commits first.
    @ObservationIgnored public var undoWindow: Duration = .seconds(FeedbackTiming.undoToastAccessible)

    private var feeds: [LookupRange: Resource<CalendarFeed>] = [:]
    private var interaction = EventInteraction()
    private var now: Date
    private var zone: ScheduleZone
    private var myUserId: String?
    @ObservationIgnored private var ranges: [LookupRange]
    @ObservationIgnored private var milestones = MilestoneCalendar.empty
    @ObservationIgnored private var milestoneValue: MilestoneIndex?
    @ObservationIgnored private var text: ScheduleText
    @ObservationIgnored private var token = 0
    @ObservationIgnored private var found: (event: CalendarEvent, range: LookupRange)?
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var joinTask: Task<Void, Never>?
    @ObservationIgnored private var chatTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    private let calendar: any CalendarRepository
    private let conversations: any ConversationsRepository
    private let session: any SessionRepository
    private let clock: any WaiveraClock
    private let memory: EventRangeMemory
    private let deviceZone: @Sendable () -> TimeZone
    private let locale: Locale

    public init(
        eventID: String,
        calendar: any CalendarRepository,
        conversations: any ConversationsRepository,
        session: any SessionRepository,
        clock: (any WaiveraClock)? = nil,
        memory: EventRangeMemory = .shared,
        deviceZone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        locale: Locale = .autoupdatingCurrent
    ) {
        self.eventID = eventID
        self.calendar = calendar
        self.conversations = conversations
        self.session = session
        let clock = clock ?? RepositoryAlignedClock(calendar: calendar)
        self.clock = clock
        self.memory = memory
        self.deviceZone = deviceZone
        self.locale = locale
        let user = session.currentState.user
        let zone = ScheduleZone.resolve(savedIdentifier: user?.timeZoneIdentifier)
        self.zone = zone
        myUserId = user?.id
        now = clock.now
        text = ScheduleText(zone: zone.timeZone, locale: locale)
        ranges = Self.ranges(for: eventID, memory: memory, today: CalendarDate(clock.now, in: zone.timeZone))
    }

    public convenience init(eventID: String, data: DataEnvironment) {
        self.init(eventID: eventID, calendar: data.calendar, conversations: data.conversations, session: data.session)
    }

    /// The remembered range, else the previous, current and next month grids around today.
    static func ranges(for eventID: String, memory: EventRangeMemory, today: CalendarDate) -> [LookupRange] {
        if let entry = memory.entry(for: eventID) { return [LookupRange(view: entry.view, anchor: entry.anchor)] }
        let month = today.firstOfMonth
        return [0, -1, 1].map { LookupRange(view: .month, anchor: month.addingMonths($0)) }
    }

    // MARK: Lifecycle

    /// Watches the lookup feeds and milestones; fetches feeds that are missing. Runs until the
    /// view's task is cancelled.
    public func observe() async {
        let calendar = calendar
        let ranges = ranges
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await resource in calendar.milestones() { await self.apply(milestones: resource) }
            }
            for range in ranges {
                group.addTask {
                    var checked = false
                    for await resource in calendar.feed(period: range.view, containing: range.anchor) {
                        await self.apply(feed: resource, for: range)
                        if !checked {
                            checked = true
                            if resource.phase != .loading, resource.value == nil || resource.updatedAt == nil {
                                await calendar.refresh(period: range.view, containing: range.anchor)
                            }
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

    /// The error state's Retry: refetch every watched range.
    public func retry() {
        refreshTask?.cancel()
        let calendar = calendar
        let targets = found.map { [$0.range] } ?? ranges
        refreshTask = Task {
            await withDiscardingTaskGroup { group in
                for range in targets {
                    group.addTask { await calendar.refresh(period: range.view, containing: range.anchor) }
                }
            }
        }
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
            // The feed is the source of truth: refetch so every screen shows the new answer.
            if let range = found?.range {
                await calendar.refresh(period: range.view, containing: range.anchor)
            }
        } catch {
            interaction.optimistic = nil
            interaction.failure = ResponseFailure(accept: accept, error: WaiveraError.from(error))
            failureTicks += 1
            rebuild()
        }
    }

    // MARK: Join and chat

    public func join() {
        guard case .loaded(let details) = state, let join = details.join, !join.isBusy, join.state == .open,
            let event = found?.event
        else { return }
        interaction.joinError = nil
        guard event.isSprout else {
            if let url = event.joinURL, WebLinks.isWebURL(url) {
                openRequest = OpenRequest(id: UUID(), url: url)
            } else {
                interaction.joinError = .noLink
                failureTicks += 1
            }
            rebuild()
            return
        }
        interaction.joinBusy = true
        rebuild()
        let calendar = calendar
        joinTask?.cancel()
        joinTask = Task {
            do {
                let url = try await calendar.meetingURL(for: event)
                self.lobbyReady(url)
            } catch {
                self.joinFailed(WaiveraError.from(error))
            }
        }
    }

    /// The view tried to open `openRequest`; `accepted` is false when no app took the link.
    public func linkHandled(_ request: OpenRequest, accepted: Bool) {
        guard openRequest?.id == request.id else { return }
        openRequest = nil
        if !accepted { joinFailed(nil) }
    }

    public func dismissJoinError() {
        interaction.joinError = nil
        rebuild()
    }

    /// Opens (or creates) the direct conversation with the organizer.
    public func messageOrganizer() {
        guard case .loaded(let details) = state, details.canMessageOrganizer, !interaction.chatBusy,
            let ownerId = found?.event.ownerId
        else { return }
        interaction.chatBusy = true
        interaction.chatError = nil
        rebuild()
        let conversations = conversations
        chatTask?.cancel()
        chatTask = Task {
            do {
                let conversation = try await conversations.openDirectConversation(with: ownerId)
                self.chatOpened(conversation.id)
            } catch {
                self.chatFailed(WaiveraError.from(error))
            }
        }
    }

    public func conversationHandled(_ request: ConversationRequest) {
        if conversationRequest?.id == request.id { conversationRequest = nil }
    }

    private func lobbyReady(_ url: URL) {
        interaction.joinBusy = false
        if WebLinks.isWebURL(url) {
            openRequest = OpenRequest(id: UUID(), url: url)
        } else {
            interaction.joinError = .failed(nil)
            failureTicks += 1
        }
        rebuild()
    }

    private func joinFailed(_ error: WaiveraError?) {
        interaction.joinBusy = false
        interaction.joinError = .failed(error)
        failureTicks += 1
        rebuild()
    }

    private func chatOpened(_ conversationId: Int) {
        interaction.chatBusy = false
        conversationRequest = ConversationRequest(id: UUID(), conversationId: conversationId)
        rebuild()
    }

    private func chatFailed(_ error: WaiveraError) {
        interaction.chatBusy = false
        interaction.chatError = error
        failureTicks += 1
        rebuild()
    }

    // MARK: State

    private func apply(feed resource: Resource<CalendarFeed>, for range: LookupRange) {
        feeds[range] = resource
        rebuild()
    }

    private func apply(milestones resource: Resource<MilestoneIndex>) {
        guard let index = resource.value, index != milestoneValue else { return }
        milestoneValue = index
        milestones = MilestoneCalendar(index)
        rebuild()
    }

    private func rebuild() {
        let lookup = lookupResult()
        switch lookup {
        case .found(let event, let range, let refreshFailed):
            found = (event, range)
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
        case found(CalendarEvent, LookupRange, refreshFailed: Bool)
        case failed(WaiveraError)
        case notFound
    }

    private func lookupResult() -> Lookup {
        for range in ranges {
            guard let resource = feeds[range], let event = resource.value?.events.first(where: { $0.id == eventID })
            else { continue }
            return .found(event, range, refreshFailed: resource.error != nil)
        }
        let resources = ranges.map { feeds[$0] }
        if resources.contains(where: { $0 == nil || ($0?.value == nil && $0?.error == nil) }) { return .loading }
        if let error = resources.compactMap({ $0?.value == nil ? $0?.error : nil }).first { return .failed(error) }
        return .notFound
    }
}
