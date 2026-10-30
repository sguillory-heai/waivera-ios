import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraRealtime

/// In-memory chat: the inbox, timelines, threads and an outbox with the same visible states
/// as the live engine (sending, failed with Retry, confirmed). Seeded from `DemoData`.
public actor FakeChatRepository {
    public enum SendOutcome: Sendable, Equatable {
        /// Confirmed at once.
        case deliver
        /// Shown as failed with Retry.
        case fail(WaiveraError)
        /// Stays "sending" until the test calls `confirmPending()`.
        case hold
    }

    nonisolated let inbox: FakeResource<[Conversation]>
    nonisolated let typingCell = StateCell<[Int: [String]]>([:])
    nonisolated let unreadCell = StateCell(0)
    nonisolated let failedSendsCell = StateCell<Set<Int>>([])
    nonisolated let timelineCells = CellRegistry<Int, Resource<MessageTimeline>>(initial: Resource())
    nonisolated let threadCells = CellRegistry<Int, Resource<ThreadTimeline>>(initial: Resource())
    nonisolated public let calls = CallLog()
    /// On-screen conversations, as the live engine tracks them for unread counts and alerts.
    nonisolated public let presence: ChatPresence

    let viewer: CurrentUser
    let clock: any WaiveraClock
    var messages: [Int: [ChatMessage]]
    var threadsById: [Int: ThreadTimeline]
    var pending: [String: OutgoingMessage] = [:]
    var loadedTimelines: Set<Int> = []
    var loadedThreads: Set<Int> = []
    nonisolated let timelineControls = LockedValue(FakeControls())
    var sendOutcome = SendOutcome.deliver
    var reactionsAvailable = true
    var markReadFailure: WaiveraError?
    /// While set, timelines report an older page and `loadOlder` fails with this error.
    var olderPageFailure: WaiveraError?
    var olderPageFailed: Set<Int> = []
    var nextMessageId = 20_000
    var nextClientId = 0
    var nextConversationId = 5_000

    public init(data: DemoData, clock: any WaiveraClock, presence: ChatPresence = ChatPresence()) {
        viewer = data.user
        self.clock = clock
        self.presence = presence
        inbox = FakeResource(data.conversations, clock: clock)
        messages = data.messages
        threadsById = data.threads
        for entry in data.pending { pending[entry.clientMessageId] = entry }
        failedSendsCell.set(Set(data.pending.filter(\.isFailed).map(\.conversationId)))
        unreadCell.set(data.conversations.reduce(0) { $0 + $1.unreadCount })
    }

    // MARK: Controls

    public func setSendOutcome(_ outcome: SendOutcome) { sendOutcome = outcome }
    nonisolated public func setTimelineControls(_ controls: FakeControls) { timelineControls.update { $0 = controls } }
    nonisolated public func setInboxControls(_ controls: FakeControls) { inbox.setControls(controls) }
    /// Reactions are hub-only; `false` behaves like a disconnected hub (gap G-01).
    public func setReactionsAvailable(_ available: Bool) { reactionsAvailable = available }
    /// `markRead` restores the unread count and throws this, as a failed server call would.
    public func setMarkReadFailure(_ failure: WaiveraError?) { markReadFailure = failure }

    public func setOlderPageFailure(_ failure: WaiveraError?) {
        olderPageFailure = failure
        for id in loadedTimelines { publishTimeline(id) }
    }

    nonisolated public func setTyping(_ userIds: [String], in conversationId: Int) {
        typingCell.update { $0[conversationId] = userIds.isEmpty ? nil : userIds }
    }

    /// Confirms every held send.
    public func confirmPending() {
        for entry in pending.values where entry.state == .sending { confirm(entry) }
    }

    /// A message from someone else arrives, as over the hub.
    public func receive(_ message: ChatMessage) {
        if let rootId = message.threadRootId {
            storeReply(message, rootId: rootId)
            return
        }
        messages[message.conversationId, default: []].append(message)
        publishTimeline(message.conversationId)
        let isOpen = calls.count("open:\(message.conversationId)") > calls.count("close:\(message.conversationId)")
        updateConversation(message.conversationId) { row in
            row.lastMessage = message
            if !message.isMine, !isOpen { row.unreadCount += 1 }
        }
    }

    // MARK: Publishing

    func publishTimeline(_ conversationId: Int, phase: ResourcePhase? = nil) {
        publishFailedSends()
        let isLoaded = loadedTimelines.contains(conversationId)
        let rows = pending.values.filter { $0.conversationId == conversationId && $0.parentMessageId == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let cell = timelineCells.cell(conversationId)
        let value =
            isLoaded
            ? MessageTimeline(
                conversationId: conversationId,
                messages: messages[conversationId] ?? [],
                pending: rows,
                hasOlder: olderPageFailure != nil,
                olderPageError: olderPageFailed.contains(conversationId) ? olderPageFailure : nil
            )
            : cell.current.value
        cell.set(Resource(value: value, phase: phase ?? cell.current.phase, updatedAt: isLoaded ? clock.now : nil))
    }

    func publishThread(_ rootId: Int, phase: ResourcePhase? = nil) {
        publishFailedSends()
        guard var thread = threadsById[rootId] else { return }
        thread.pending = pending.values.filter { $0.parentMessageId == rootId }.sorted { $0.createdAt < $1.createdAt }
        let cell = threadCells.cell(rootId)
        let value = loadedThreads.contains(rootId) ? thread : cell.current.value
        cell.set(Resource(value: value, phase: phase ?? cell.current.phase, updatedAt: clock.now))
    }

    /// Conversations with a failed send, as the live engine publishes them.
    func publishFailedSends() {
        let failed = Set(pending.values.filter(\.isFailed).map(\.conversationId))
        if failed != failedSendsCell.current { failedSendsCell.set(failed) }
    }

    func updateConversation(_ id: Int, _ change: (inout Conversation) -> Void) {
        inbox.mutate { rows in
            guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
            change(&rows[index])
            rows.sort { ($0.activityDate ?? .distantPast) > ($1.activityDate ?? .distantPast) }
        }
        unreadCell.set((inbox.value ?? []).reduce(0) { $0 + $1.unreadCount })
    }

    func updateMessage(_ id: Int, conversationId: Int, _ change: (inout ChatMessage) -> Void) {
        if let index = messages[conversationId]?.firstIndex(where: { $0.id == id }) {
            change(&messages[conversationId, default: []][index])
            publishTimeline(conversationId)
        }
        for (rootId, thread) in threadsById where thread.conversationId == conversationId {
            var updated = thread
            if updated.root?.id == id, var root = updated.root {
                change(&root)
                updated.root = root
            }
            if let index = updated.replies.firstIndex(where: { $0.id == id }) { change(&updated.replies[index]) }
            if updated != thread {
                threadsById[rootId] = updated
                publishThread(rootId)
            }
        }
    }

    func storeReply(_ reply: ChatMessage, rootId: Int) {
        var thread =
            threadsById[rootId]
            ?? ThreadTimeline(
                rootMessageId: rootId,
                conversationId: reply.conversationId,
                root: messages[reply.conversationId]?.first { $0.id == rootId }
            )
        guard !thread.replies.contains(where: { $0.id == reply.id }) else { return }
        thread.replies.append(reply)
        threadsById[rootId] = thread
        updateMessage(rootId, conversationId: reply.conversationId) { $0.threadReplyCount += 1 }
        publishThread(rootId)
    }
}

extension FakeChatRepository: ConversationsRepository {
    nonisolated public func conversations() -> AsyncStream<Resource<[Conversation]>> { inbox.stream() }
    nonisolated public func typing() -> AsyncStream<[Int: [String]]> { typingCell.stream() }
    nonisolated public func totalUnread() -> AsyncStream<Int> { unreadCell.stream() }
    nonisolated public func failedSends() -> AsyncStream<Set<Int>> { failedSendsCell.stream() }

    public func refresh() async {
        calls.record("refreshInbox")
        await inbox.refresh()
    }

    public func conversation(id: Int) async throws -> Conversation {
        guard let row = inbox.value?.first(where: { $0.id == id }) else { throw WaiveraError.notFound }
        return row
    }

    public func openDirectConversation(with userId: String) async throws -> Conversation {
        if let existing = inbox.value?.first(where: { row in
            row.kind == .direct && row.participants.contains { $0.id == userId }
        }) {
            return existing
        }
        return insertConversation(kind: .direct, participantIds: [userId])
    }

    public func createConversation(participantIds: [String]) async throws -> Conversation {
        insertConversation(kind: participantIds.count > 1 ? .group : .direct, participantIds: participantIds)
    }

    public func leave(conversationId: Int) async throws {
        calls.record("leave:\(conversationId)")
        inbox.mutate { $0.removeAll { $0.id == conversationId } }
        unreadCell.set((inbox.value ?? []).reduce(0) { $0 + $1.unreadCount })
    }

    private func insertConversation(kind: Conversation.Kind, participantIds: [String]) -> Conversation {
        nextConversationId += 1
        let participants = [viewer.asChatUser] + participantIds.map { ChatUser(id: $0) }
        let row = Conversation(id: nextConversationId, kind: kind, viewerId: viewer.id, participants: participants)
        inbox.mutate { $0.insert(row, at: 0) }
        return row
    }
}
