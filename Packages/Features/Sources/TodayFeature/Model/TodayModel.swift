import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Where a Today row leads. The view turns each case into the router closure it was given.
enum TodayDestination: Hashable, Sendable {
    case chat(ChatDestination)
    case event(id: String)
    case schedule
    case activity
}

/// Today: one prioritised list rendered from the repositories' cached values first, then
/// refreshed. Every write is optimistic and put back on failure; nothing blocks on the network.
@MainActor
@Observable
final class TodayModel {
    /// How long an invitation answer waits for Undo before it is sent (Android's long snackbar).
    static let invitationUndoWindow: Duration = .seconds(10)

    private(set) var state = TodayState()
    let feedback = TodayFeedback()
    /// The chat "Send wishes" opened, for the view to follow once.
    private(set) var wishesRequest: WishesRequest?

    @ObservationIgnored let environment: DataEnvironment
    @ObservationIgnored let clock: any WaiveraClock
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored let tasks = TaskBag()
    @ObservationIgnored let activity: ActivityController
    @ObservationIgnored var sources = TodaySources()
    @ObservationIgnored private var local = TodayLocalState()
    @ObservationIgnored var now: Date
    @ObservationIgnored var connection: ConnectionBanner = .hidden
    @ObservationIgnored private var navigation = NavigationGuard()
    @ObservationIgnored var scheduleAnchors: [CalendarDate] = []
    @ObservationIgnored var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var failingSources: Set<String> = []
    @ObservationIgnored private let handledStore: any HandledTallyStore
    @ObservationIgnored private var handled: HandledTally?
    @ObservationIgnored var user: CurrentUser?
    /// Invitation answers inside their Undo window, by event id.
    @ObservationIgnored private var heldAnswers: [String: HeldAnswer] = [:]
    @ObservationIgnored private var answerToken = 0
    @ObservationIgnored private var wishesCount = 0

    init(
        environment: DataEnvironment,
        clock: any WaiveraClock,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        handledStore: any HandledTallyStore = KeyValueHandledTallyStore(store: UserDefaultsKeyValueStore())
    ) {
        self.environment = environment
        self.clock = clock
        self.uptime = uptime
        self.handledStore = handledStore
        handled = handledStore.load()
        user = environment.session.currentState.user
        now = clock.now
        activity = ActivityController(repository: environment.activity, feedback: feedback, tasks: tasks)
        activity.onChange = { [weak self] in self?.rebuild() }
        rebuild()
    }

    /// Runs while the screen is visible (`.task`): follows every source, ticks the clock and
    /// refreshes whatever is stale. Cancelling the task stops all of it.
    func run() async {
        now = clock.now
        startSchedule()
        defer {
            scheduleTask?.cancel()
            scheduleTask = nil
        }
        await withDiscardingTaskGroup { group in
            group.addTask { await self.observeConversations() }
            group.addTask { await self.observeFailedSends() }
            group.addTask { await self.activity.observe() }
            group.addTask { await self.observeMilestones() }
            group.addTask { await self.observeConnection() }
            group.addTask { await self.observeSession() }
            group.addTask { await self.tick() }
            group.addTask { await self.refreshStaleSources() }
        }
    }

    // MARK: Actions

    /// Pull to refresh: every source at once. Failures keep the cached content and show a toast.
    func refresh() async {
        guard !local.isRefreshing else { return }
        local.isRefreshing = true
        rebuild()
        let conversations = environment.conversations
        let calendar = environment.calendar
        async let chats: Void = conversations.refresh()
        async let feed = activity.refresh()
        async let weeks: Void = refreshSchedule()
        async let milestones: Void = calendar.refreshMilestones()
        _ = await (chats, feed, weeks, milestones)
        sources.conversations = await latest(conversations.conversations()) ?? sources.conversations
        local.isRefreshing = false
        rebuild()
    }

    func toggleNeedsYouExpanded() {
        local.needsYouExpanded.toggle()
        rebuild()
    }

    func setFilter(_ filter: ActivityFilter) { activity.setFilter(filter) }
    func toggleUnreadOnly() { activity.toggleUnreadOnly() }
    func clearActivityFilters() { activity.clearFilters() }
    func markRead(_ activityId: Int64) { activity.markRead(activityId) }
    func markAllRead() { activity.markAllRead() }
    func loadMoreActivity() { activity.loadMoreIfPossible() }
    func retryMoreActivity() { activity.retryMore() }

    /// Accept or Decline from Needs you. The row leaves at once and the toast offers Undo; the
    /// answer goes out when the toast closes without Undo, or after `invitationUndoWindow`
    /// (Android `InvitationAnswers`). A failed send brings the row back with Retry.
    func respond(toEventId eventId: String, accept: Bool) {
        guard heldAnswers[eventId] == nil else { return }
        local.answeredInvitations.insert(eventId)
        rebuild()
        answerToken += 1
        let token = answerToken
        let clock = clock
        let calendar = environment.calendar
        // Not in `tasks`: an answer still waiting when Today goes away is the person's decision,
        // so it is sent even after the model is released.
        let timer = Task { [weak self] in
            do {
                try await clock.sleep(for: Self.invitationUndoWindow)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            if let self {
                self.sendHeldAnswer(eventId: eventId, token: token)
            } else {
                try? await calendar.respond(toEventId: eventId, accept: accept)
            }
        }
        heldAnswers[eventId] = HeldAnswer(accept: accept, token: token, timer: timer)
        feedback.show(.invitationAnswered(eventId: eventId, accept: accept, token: token))
    }

    /// Undo on the toast: the answer was never sent, so the invitation simply comes back.
    func undoInvitation(eventId: String, token: Int) {
        guard let held = heldAnswers[eventId], held.token == token else { return }
        held.timer.cancel()
        heldAnswers[eventId] = nil
        local.answeredInvitations.remove(eventId)
        rebuild()
    }

    /// The toast went away: timed out, dismissed or replaced. An answer it was holding goes out
    /// now rather than waiting out the window.
    func toastClosed(_ toast: TodayToast) {
        feedback.dismiss(toast.id)
        if case .invitationAnswered(let eventId, _, let token) = toast.notice {
            sendHeldAnswer(eventId: eventId, token: token)
        }
    }

    /// The toast's action: Undo for an answered invitation, Retry for everything else.
    func toastAction(_ toast: TodayToast) {
        if case .invitationAnswered(let eventId, _, let token) = toast.notice {
            feedback.dismiss(toast.id)
            undoInvitation(eventId: eventId, token: token)
        } else {
            retry(toast)
        }
    }

    /// The toast's Retry.
    func retry(_ toast: TodayToast) {
        feedback.dismiss(toast.id)
        switch toast.notice {
        case .refreshFailed: tasks.run { [weak self] in await self?.refresh() }
        case .markReadFailed(let id): activity.markRead(id)
        case .markAllFailed: activity.markAllRead()
        case .invitationFailed(let eventId, let accept):
            // A decision already made: it goes straight out, with no second Undo.
            guard heldAnswers[eventId] == nil else { return }
            local.answeredInvitations.insert(eventId)
            rebuild()
            send(eventId: eventId, accept: accept)
        case .wishesFailed(let userId): sendWishes(to: userId)
        case .invitationAnswered: break
        }
    }

    /// "Send wishes" on a celebration card: opens (or starts) the direct chat with the
    /// celebrated person. The button shows it is opening from the tap; a second tap meanwhile is
    /// ignored, so one tap never opens two chats. Never on your own card.
    func sendWishes(to userId: String) {
        let viewerId = user?.id ?? environment.session.currentState.user?.id
        guard local.openingWishesFor == nil, userId != viewerId else { return }
        local.openingWishesFor = userId
        rebuild()
        let conversations = environment.conversations
        tasks.run { [weak self] in
            let result: Result<Int, WaiveraError>
            do {
                result = .success(try await conversations.openDirectConversation(with: userId).id)
            } catch {
                result = .failure(WaiveraError.from(error))
            }
            self?.finishWishes(userId: userId, result: result)
        }
    }

    /// The view followed `request`; it is not offered again.
    func wishesHandled(_ request: WishesRequest) {
        if wishesRequest == request { wishesRequest = nil }
    }

    private func finishWishes(userId: String, result: Result<Int, WaiveraError>) {
        local.openingWishesFor = nil
        rebuild()
        switch result {
        case .success(let conversationId):
            wishesCount += 1
            wishesRequest = WishesRequest(id: wishesCount, conversationId: conversationId)
        case .failure:
            feedback.fail(.wishesFailed(userId: userId))
        }
    }

    private func sendHeldAnswer(eventId: String, token: Int) {
        guard let held = heldAnswers[eventId], held.token == token else { return }
        held.timer.cancel()
        heldAnswers[eventId] = nil
        send(eventId: eventId, accept: held.accept)
    }

    private func send(eventId: String, accept: Bool) {
        let calendar = environment.calendar
        tasks.run { [weak self] in
            do {
                try await calendar.respond(toEventId: eventId, accept: accept)
                self?.feedback.succeed()
                await self?.refreshSchedule()
            } catch {
                guard let self else { return }
                local.answeredInvitations.remove(eventId)
                rebuild()
                feedback.fail(.invitationFailed(eventId: eventId, accept: accept))
            }
        }
    }

    /// Whether to follow a tap: drops a second navigation within 600 ms. Opening an activity or
    /// a pinned mention also marks it read.
    func navigate(to destination: TodayDestination, markingRead activityId: Int64? = nil) -> TodayDestination? {
        guard navigation.allows(at: uptime()) else { return nil }
        if let activityId { activity.markRead(activityId) }
        return destination
    }

    // MARK: State

    private var zone: (zone: TimeZone, isFallback: Bool) { environment.calendar.scheduleTimeZone() }
    var today: CalendarDate { CalendarDate(now, in: zone.zone) }

    func rebuild() {
        var current = sources
        current.activity = activity.resource
        let zone = zone
        let context = TodayContext(
            accountName: user.map(Self.accountName) ?? "",
            myUserId: user?.id,
            firstName: GreetingRules.firstName(user?.firstName, displayName: user?.displayName),
            handled: handled,
            zone: zone.zone,
            usesFallbackTimeZone: zone.isFallback,
            now: now,
            connection: connection,
            local: local,
            activity: activity.local
        )
        let next = TodayAssembler.assemble(current, context: context)
        record(next.handledObservation)
        if next != state { state = next }
        noticeFailures(current)
    }

    /// Saves the tally as the ring already shows it (`HandledRules.progress` worked it out from
    /// the same observation), so the ring and the store never disagree.
    private func record(_ observation: HandledObservation?) {
        guard let observation else { return }
        let advanced = HandledToday.advance(handled, observation)
        guard advanced != handled else { return }
        handled = advanced
        handledStore.save(advanced)
    }

    private static func accountName(_ user: CurrentUser) -> String {
        let full = [user.firstName, user.lastName].compactMap { $0?.trimmedNonEmpty }.joined(separator: " ")
        return user.displayName?.trimmedNonEmpty ?? full.trimmedNonEmpty ?? user.email ?? ""
    }

    /// A refresh that failed while cached content is on screen gets one quiet toast; the cached
    /// content stays. Offline already says so in the quiet line.
    private func noticeFailures(_ current: TodaySources) {
        var failing = Set<String>()
        if current.conversations.error != nil, current.conversations.value?.isEmpty == false { failing.insert("chats") }
        if current.activity.error != nil, current.activity.value?.items.isEmpty == false { failing.insert("activity") }
        for (index, week) in current.schedule.enumerated() where week.error != nil && week.value?.isEmpty == false {
            failing.insert("week-\(index)")
        }
        let newlyFailing = failing.subtracting(failingSources)
        failingSources = failing
        if !newlyFailing.isEmpty, connection != .offline {
            feedback.show(.refreshFailed)
        }
    }
}

/// An invitation answer inside its Undo window.
private struct HeldAnswer {
    let accept: Bool
    let token: Int
    let timer: Task<Void, Never>
}

/// A chat "Send wishes" opened. `id` makes a second request for the same chat a new value.
struct WishesRequest: Equatable, Sendable {
    let id: Int
    let conversationId: Int
}
