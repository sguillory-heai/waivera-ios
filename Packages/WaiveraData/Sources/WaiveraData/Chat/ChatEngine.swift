import Foundation
import WaiveraAPI
import WaiveraRealtime

/// The chat source of truth for one signed-in session: the inbox, every open timeline and
/// thread, and the outbox. Screens read it through `ConversationsRepository`,
/// `MessagesRepository` and `ThreadsRepository`; `RealtimeIngestor` feeds it hub events.
///
/// Everything lives in this one actor so a hub event, a REST page and an optimistic send can
/// never interleave half-applied.
public actor ChatEngine {
    struct TimelineState {
        var messages: [Int: ChatMessage] = [:]
        var hasOlder = false
        var isLoaded = false
        var isLoadingOlder = false
        var phase: ResourcePhase = .idle
        var updatedAt: Date?
        /// Hub messages that arrived before the first page (05 §5: never synthesize a page).
        var buffered: [ChatMessage] = []
    }

    struct ThreadState {
        var conversationId: Int
        var root: ChatMessage?
        var replies: [Int: ChatMessage] = [:]
        var isLoaded = false
        var phase: ResourcePhase = .idle
        var updatedAt: Date?
    }

    /// Automatic attempts before a send shows Retry.
    static let maxAutomaticAttempts = 3
    /// Text-match window for servers that do not echo the client id (03 §11).
    static let reconcileWindow: TimeInterval = 60
    static let hydrationBatchSize = 6

    let api: APIClient
    let realtime: any RealtimeClient
    let store: any LocalStore
    let clock: any WaiveraClock
    nonisolated let presence: ChatPresence
    nonisolated let typingTracker: TypingTracker
    let alertPreferences: @Sendable () -> NotificationPreferences

    var viewer: CurrentUser?
    /// Bumped on every sign-in and sign-out; stale tasks check it before writing.
    var generation = 0

    var conversationsById: [Int: Conversation] = [:]
    var conversationsPhase: ResourcePhase = .idle
    var conversationsUpdatedAt: Date?
    var conversationsLoad: Task<Void, Never>?
    nonisolated let conversationsCell = StateCell(Resource<[Conversation]>())
    nonisolated let unreadCell = StateCell(0)

    var timelines: [Int: TimelineState] = [:]
    nonisolated let timelineCells = CellRegistry<Int, Resource<MessageTimeline>>(initial: Resource())
    var openConversations: [Int: Int] = [:]

    var threads: [Int: ThreadState] = [:]
    nonisolated let threadCells = CellRegistry<Int, Resource<ThreadTimeline>>(initial: Resource())
    var openThreads: [Int: Int] = [:]

    var outbox: [String: OutgoingMessage] = [:]
    var outboxTasks: [String: Task<Void, Never>] = [:]
    var lastReadThrough: [String: Int] = [:]
    /// Cache writes run one after another so an older snapshot never lands last.
    var persistence: Task<Void, Never>?

    nonisolated let alertBroadcaster = AsyncBroadcaster<ChatAlert>(replays: false)
    /// Read-state changes for the activity feed (03 §12).
    nonisolated let readStateBroadcaster = AsyncBroadcaster<ChatReadState>(replays: false)
    lazy var throttle = TypingThrottle(clock: clock) { [realtime] conversationId, isTyping in
        await realtime.sendTypingStatus(conversationId: conversationId, isTyping: isTyping)
    }

    public init(
        api: APIClient,
        realtime: any RealtimeClient,
        store: any LocalStore,
        clock: any WaiveraClock,
        presence: ChatPresence,
        alertPreferences: @escaping @Sendable () -> NotificationPreferences = { NotificationPreferences() }
    ) {
        self.api = api
        self.realtime = realtime
        self.store = store
        self.clock = clock
        self.presence = presence
        self.alertPreferences = alertPreferences
        typingTracker = TypingTracker(clock: clock)
    }

    var mapper: ChatMapper? { viewer.map { ChatMapper(viewerId: $0.id) } }

    // MARK: Session

    /// A user signed in: render the cached inbox and outbox at once, then refresh.
    public func begin(user: CurrentUser) async {
        await end()
        viewer = user
        let current = generation
        if let cached = await store.load([Conversation].self, for: .conversations), generation == current {
            for conversation in cached where conversation.viewerId == user.id {
                conversationsById[conversation.id] = conversation
            }
            publishConversations()
        }
        if let pending = await store.load([OutgoingMessage].self, for: .outbox), generation == current {
            for message in pending { outbox[message.clientMessageId] = message }
            resumeOutbox()
        }
    }

    /// Sign-out: drop everything in memory. The caller wipes the `LocalStore`.
    public func end() async {
        generation += 1
        viewer = nil
        conversationsLoad?.cancel()
        conversationsLoad = nil
        for task in outboxTasks.values { task.cancel() }
        outboxTasks.removeAll()
        conversationsById.removeAll()
        conversationsPhase = .idle
        conversationsUpdatedAt = nil
        timelines.removeAll()
        threads.removeAll()
        outbox.removeAll()
        lastReadThrough.removeAll()
        openConversations.removeAll()
        openThreads.removeAll()
        presence.reset()
        await typingTracker.clearAll()
        publishConversations()
        timelineCells.resetAll()
        threadCells.resetAll()
    }

    // MARK: Publishing

    func publishConversations() {
        let rows = conversationsById.values.sorted(by: Self.inboxOrder)
        // Never loaded and nothing cached: no value, so a first failure is not an empty inbox.
        let value: [Conversation]? = conversationsUpdatedAt == nil && rows.isEmpty ? nil : rows
        conversationsCell.set(Resource(value: value, phase: conversationsPhase, updatedAt: conversationsUpdatedAt))
        let unread = rows.reduce(0) { $0 + $1.unreadCount }
        if unread != unreadCell.current { unreadCell.set(unread) }
    }

    /// Newest activity first; rows without a date sink, ties break by id.
    static func inboxOrder(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        switch (lhs.activityDate, rhs.activityDate) {
        case (let left?, let right?) where left != right: left > right
        case (.some, nil): true
        case (nil, .some): false
        default: lhs.id > rhs.id
        }
    }

    /// Oldest first; ties break by id (03 §3).
    static func messageOrder(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case (let left?, let right?) where left != right: left < right
        default: lhs.id < rhs.id
        }
    }

    func publishTimeline(_ conversationId: Int) {
        let state = timelines[conversationId] ?? TimelineState()
        let pending = outbox.values.filter { $0.conversationId == conversationId && $0.parentMessageId == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let value: MessageTimeline? =
            state.isLoaded || !pending.isEmpty || !state.messages.isEmpty
            ? MessageTimeline(
                conversationId: conversationId,
                messages: state.messages.values.sorted(by: Self.messageOrder),
                pending: pending,
                hasOlder: state.hasOlder,
                isLoadingOlder: state.isLoadingOlder
            ) : nil
        timelineCells.cell(conversationId).set(Resource(value: value, phase: state.phase, updatedAt: state.updatedAt))
    }

    func publishThread(_ rootMessageId: Int) {
        guard let state = threads[rootMessageId] else { return }
        let pending = outbox.values.filter { $0.parentMessageId == rootMessageId }.sorted {
            $0.createdAt < $1.createdAt
        }
        let value: ThreadTimeline? =
            state.isLoaded || state.root != nil || !pending.isEmpty
            ? ThreadTimeline(
                rootMessageId: rootMessageId,
                conversationId: state.conversationId,
                root: state.root,
                replies: state.replies.values.sorted(by: Self.messageOrder),
                pending: pending
            ) : nil
        threadCells.cell(rootMessageId).set(Resource(value: value, phase: state.phase, updatedAt: state.updatedAt))
    }

    func enqueuePersist(_ work: @escaping @Sendable () async -> Void) {
        let previous = persistence
        persistence = Task {
            await previous?.value
            await work()
        }
    }

    func persistConversations() {
        let rows = Array(conversationsById.values)
        let store = store
        enqueuePersist { await store.save(rows, for: .conversations) }
    }

    /// Keeps the newest page of each timeline on disk for an instant first frame.
    func persistTimeline(_ conversationId: Int) {
        guard let state = timelines[conversationId], state.isLoaded else { return }
        let newest = Array(state.messages.values.sorted(by: Self.messageOrder).suffix(APIClient.messagePageSize))
        let store = store
        enqueuePersist { await store.save(newest, for: .messages(conversationId)) }
    }

    func persistOutbox() {
        let entries = Array(outbox.values)
        let store = store
        enqueuePersist { await store.save(entries, for: .outbox) }
    }

    /// Waits for queued cache writes (tests, sign-out).
    public func flushPersistence() async {
        await persistence?.value
    }
}
