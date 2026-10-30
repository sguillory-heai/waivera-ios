import Foundation
import Observation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// The inbox's state and actions (02). Free of SwiftUI so it is tested on Linux over the
/// WaiveraTestSupport fakes; `ConversationListView` owns one.
///
/// Rows render from the repository stream, which starts from the offline cache, so a cold
/// start with a cached inbox shows rows before the network answers; the server stays
/// authoritative. Merging thin previews, sparse-preview hydration (six at a time) and the
/// unread rules live in the data layer (`ChatEngine`); this model only presents them.
@MainActor
@Observable
final class ChatListModel {
    /// Revisiting the tab within this long does not refetch (02 §2 `staleTime`).
    static let staleAfter: TimeInterval = 60
    /// Arrival wash length: 180 ms in, 180 ms hold, 900 ms out (02 §4 "Arrival pulse").
    static let arrivalDuration: Duration = .milliseconds(1_260)
    /// How long a row marked read under Unread shows its cleared badge before it leaves.
    nonisolated static let removalBeat: TimeInterval = MotionTiming.removalBeat
    /// How many rows from the top get their avatars warmed (02 §4b).
    static let avatarRows = 30

    private(set) var state = ChatListState()

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            orderHold.rebase(liveOrderIds())
            rebuild()
        }
    }

    var filter = ChatListFilter.all {
        didSet {
            guard filter != oldValue else { return }
            leavingRead = []
            orderHold.rebase(liveOrderIds())
            rebuild()
        }
    }

    /// Peers of the first rows, for `AvatarPrefetcher` (02 §4b).
    private(set) var avatarUserIds: [String] = []

    @ObservationIgnored let conversations: any ConversationsRepository
    @ObservationIgnored private let messages: any MessagesRepository
    @ObservationIgnored let session: any SessionRepository
    @ObservationIgnored let realtimeStatus: any RealtimeStatusRepository
    @ObservationIgnored private let callURL: @Sendable (Conversation) async throws -> URL
    @ObservationIgnored let failedSendsSource: @Sendable () -> AsyncStream<Set<Int>>
    @ObservationIgnored private let text: any ChatListText
    @ObservationIgnored let clock: any WaiveraClock
    @ObservationIgnored private let timeFormatter: RelativeTimeFormatter

    @ObservationIgnored private var resource = Resource<[Conversation]>()
    @ObservationIgnored var typing: [Int: [String]] = [:]
    /// Conversations with a message of mine that never went out (the outbox's failed sends).
    @ObservationIgnored var failedSends: Set<Int> = []
    /// Rows just marked read under the Unread filter: they stay for the removal beat, so the
    /// badge is seen to clear before the row leaves.
    @ObservationIgnored private var leavingRead: Set<Int> = []
    @ObservationIgnored var user: CurrentUser?
    @ObservationIgnored var banner = ConnectionBanner.hidden
    @ObservationIgnored var isHubConnected = false
    @ObservationIgnored var hubEpoch = 0
    @ObservationIgnored var now: Date
    @ObservationIgnored private var openingCallId: Int?
    @ObservationIgnored private var arrivals: [Int: Int] = [:]
    /// Conversation id → the last message id (0 for none) it had when marked read here, until
    /// the repository confirms (unread 0) or a newer message arrives.
    @ObservationIgnored private var optimisticRead: [Int: Int] = [:]
    /// Last message id per conversation, to spot arrivals. `nil` until the first value.
    @ObservationIgnored private var baseline: [Int: Int]?
    @ObservationIgnored private var orderHold = InboxOrderHold()
    @ObservationIgnored private var isAtTop = true
    @ObservationIgnored private var navigationLocked = false
    @ObservationIgnored var isRefreshing = false
    @ObservationIgnored var checkedStaleness = false

    init(
        conversations: any ConversationsRepository,
        messages: any MessagesRepository,
        session: any SessionRepository,
        realtimeStatus: any RealtimeStatusRepository,
        callURL: @escaping @Sendable (Conversation) async throws -> URL,
        failedSends: @escaping @Sendable () -> AsyncStream<Set<Int>> = ChatListModel.noFailedSends,
        text: any ChatListText,
        clock: any WaiveraClock,
        locale: Locale = .current
    ) {
        self.conversations = conversations
        self.messages = messages
        self.session = session
        self.realtimeStatus = realtimeStatus
        self.callURL = callURL
        failedSendsSource = failedSends
        self.text = text
        self.clock = clock
        timeFormatter = RelativeTimeFormatter(text: text, locale: locale)
        now = clock.now
        user = session.currentState.user
    }

    /// The screen's model over the data layer. `text` and `locale` are the device's own unless a
    /// test pins them.
    convenience init(
        environment: DataEnvironment,
        text: any ChatListText = LocalizedChatListText(),
        locale: Locale = .current
    ) {
        self.init(
            conversations: environment.conversations,
            messages: environment.messages,
            session: environment.session,
            realtimeStatus: environment.realtimeStatus,
            callURL: environment.callURL,
            failedSends: { [conversations = environment.conversations] in conversations.failedSends() },
            text: text,
            clock: environment.clock,
            locale: locale
        )
    }

    /// For tests and previews with no outbox: no row says "Not sent".
    nonisolated static let noFailedSends: @Sendable () -> AsyncStream<Set<Int>> = {
        AsyncStream { $0.finish() }
    }

    // MARK: Lifecycle

    /// Subscribes to every stream until the calling task is cancelled (the view's `.task`).
    /// Streams replay their current value, so restarting after a push and pop is cheap.
    func start() async {
        checkedStaleness = false
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeConversations() }
            group.addTask { await self.observeTyping() }
            group.addTask { await self.observeSession() }
            group.addTask { await self.observeBanner() }
            group.addTask { await self.observeStatuses() }
            group.addTask { await self.observeFailedSends() }
            group.addTask { await self.tick() }
        }
    }

    /// The list is visible again: a row tap may navigate again (02 §6).
    func appeared() {
        navigationLocked = false
    }

    /// Pull to refresh, and Retry on the error state or the refresh banner.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        orderHold.release()
        await conversations.refresh()
        isRefreshing = false
    }

    func retryConnection() async {
        await realtimeStatus.retryNow()
    }

    // MARK: Scroll position

    /// The list's first row is on screen (or not). While away from the top, rows hold their
    /// order so a realtime reorder never moves what the person is reading.
    func setAtTop(_ atTop: Bool) {
        guard atTop != isAtTop else { return }
        isAtTop = atTop
        if atTop {
            orderHold.release()
        } else {
            orderHold.hold(liveOrderIds())
        }
        rebuild()
    }

    /// The "New activity" pill: show the live order; the view scrolls to the top.
    func showNewActivity() {
        orderHold.release()
        rebuild()
    }

    // MARK: Row actions

    /// Guards against a fast double tap pushing the conversation twice (02 §6). Returns
    /// whether the caller should navigate.
    func open(conversationId: Int) -> Bool {
        guard !navigationLocked else { return false }
        navigationLocked = true
        return true
    }

    /// Optimistic: the badge clears at once; the data layer sends `MarkAsRead` (hub, else REST).
    /// On failure it restores the unread count, the badge comes back and a notice offers Retry.
    func markRead(conversationId: Int) {
        guard let conversation = conversation(conversationId), conversation.unreadCount > 0,
            optimisticRead[conversationId] == nil
        else { return }
        optimisticRead[conversationId] = conversation.lastMessage?.id ?? 0
        if state.notice?.kind == .markReadFailed(conversationId: conversationId) { state.notice = nil }
        if filter == .unread { holdLeavingRow(conversationId) }
        rebuild()
        let messages = messages
        Task {
            do {
                try await messages.markRead(conversationId: conversationId)
            } catch {
                self.markReadFailed(conversationId: conversationId)
            }
        }
    }

    /// The removal beat (`MotionTiming.removalBeat`): the read row shows its cleared badge, then leaves.
    private func holdLeavingRow(_ conversationId: Int) {
        leavingRead.insert(conversationId)
        let clock = clock
        Task { [weak self] in
            try? await clock.sleep(for: .milliseconds(Int(Self.removalBeat * 1_000)))
            self?.releaseLeavingRow(conversationId)
        }
    }

    private func releaseLeavingRow(_ conversationId: Int) {
        guard leavingRead.remove(conversationId) != nil else { return }
        rebuild()
    }

    private func markReadFailed(conversationId: Int) {
        optimisticRead[conversationId] = nil
        state.notice = ChatListNotice(.markReadFailed(conversationId: conversationId))
        rebuild()
    }

    /// The web lobby for a live call (03 §19). Only one call opens at a time. Returns an
    /// `https` URL, or `nil` after posting a notice with Retry.
    func joinCall(conversationId: Int) async -> URL? {
        guard openingCallId == nil, let conversation = conversation(conversationId) else { return nil }
        openingCallId = conversationId
        state.notice = nil
        rebuild()
        defer {
            openingCallId = nil
            rebuild()
        }
        do {
            let url = try await callURL(conversation)
            // Payload-derived URLs are untrusted (11-pitfalls #15).
            guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
                throw WaiveraError.invalidResponse
            }
            return url
        } catch {
            state.notice = ChatListNotice(.callFailed(conversationId: conversationId))
            return nil
        }
    }

    func dismissNotice() {
        state.notice = nil
    }
}

extension ChatListModel {
    // MARK: Applying values

    func apply(_ next: Resource<[Conversation]>) {
        resource = next
        let rows = next.value ?? []
        detectArrivals(rows)
        for (id, markedAt) in optimisticRead {
            guard let row = rows.first(where: { $0.id == id }) else {
                optimisticRead[id] = nil
                continue
            }
            if row.unreadCount == 0 || (row.lastMessage?.id ?? 0) != markedAt { optimisticRead[id] = nil }
        }
        rebuild()
    }

    private func detectArrivals(_ rows: [Conversation]) {
        let latest = Dictionary(rows.compactMap { row in row.lastMessage.map { (row.id, $0.id) } }) { first, _ in first
        }
        defer { if !rows.isEmpty { baseline = latest } }
        guard let previous = baseline else { return }
        for row in rows {
            guard let message = row.lastMessage, !message.isMine, message.id > (previous[row.id] ?? 0) else {
                continue
            }
            arrivals[row.id] = message.id
            let clock = clock
            Task { [weak self] in
                try? await clock.sleep(for: Self.arrivalDuration)
                self?.endArrival(conversationId: row.id, messageId: message.id)
            }
        }
    }

    private func endArrival(conversationId: Int, messageId: Int) {
        guard arrivals[conversationId] == messageId else { return }
        arrivals[conversationId] = nil
        rebuild()
    }

    func updateConnection() {
        let next = Self.connection(banner: banner, isConnected: isHubConnected, epoch: hubEpoch)
        if next != state.connection { state.connection = next }
    }

    /// The pill: the device being offline wins, then the hub state. Before the first connect
    /// the hub is "Connecting"; once it has connected, a stopped hub is "Offline".
    nonisolated static func connection(
        banner: ConnectionBanner,
        isConnected: Bool,
        epoch: Int
    ) -> ConnectionIndicator {
        switch banner {
        case .offline: return .offline
        case .reconnecting: return .reconnecting
        case .connecting: return .connecting
        case .hidden:
            if isConnected { return .online }
            return epoch == 0 ? .connecting : .offline
        }
    }

    private func conversation(_ id: Int) -> Conversation? {
        resource.value?.first { $0.id == id }
    }

    private func liveOrderIds() -> [Int] {
        (resource.value ?? []).sorted(by: ConversationPresentation.inboxOrder).map(\.id)
    }

    // MARK: State building

    func rebuild() {
        var next = state
        next.refreshError = nil
        guard let all = resource.value else {
            next.rows = []
            next.hasPendingReorder = false
            next.content = resource.error.map(ChatListContent.error) ?? .loading
            if !avatarUserIds.isEmpty { avatarUserIds = [] }
            commit(next)
            return
        }
        let zone = user?.scheduleTimeZone ?? .current
        let built = all.sorted(by: ConversationPresentation.inboxOrder).map { row($0, zone: zone) }
            .filter {
                ConversationPresentation.matches($0, filter: filter, query: query) || leavingRead.contains($0.id)
            }
        let arranged = orderHold.arrange(built.map(\.id))
        let builtById = Dictionary(built.map { ($0.id, $0) }) { first, _ in first }
        next.rows = arranged.order.compactMap { builtById[$0] }
        next.hasPendingReorder = arranged.hasPending
        next.content =
            next.rows.isEmpty ? .empty(ConversationPresentation.emptyReason(filter: filter, query: query)) : .rows
        next.refreshError = resource.error
        let peers = next.rows.prefix(Self.avatarRows).compactMap(\.profileUserId)
        if peers != avatarUserIds { avatarUserIds = peers }
        commit(next)
    }

    private func commit(_ next: ChatListState) { if next != state { state = next } }

    private func row(_ conversation: Conversation, zone: TimeZone) -> ChatRow {
        ChatRowBuilder(
            text: text,
            typingUserIds: typing[conversation.id] ?? [],
            timeLabel: timeFormatter.label(for: conversation.lastMessage?.createdAt, now: now, timeZone: zone),
            isMarkedRead: optimisticRead[conversation.id] != nil,
            isOpeningCall: openingCallId == conversation.id,
            arrivalKey: arrivals[conversation.id],
            isSendFailed: failedSends.contains(conversation.id)
        ).row(conversation)
    }
}
