import Foundation
import Observation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// A thread (04): the root message, its replies oldest first and a text-only reply composer.
/// It wires the full action sheet and reactions (parity fix), and opening it joins the
/// conversation's hub group, so a thread opened from a notification still gets live replies.
@MainActor
@Observable
final class ThreadModel {
    static let highlightScrollDelay = 0.12

    let rootMessageID: Int
    let conversationID: Int?
    let targetMessageID: Int?
    /// Set only by this model and its extensions.
    var state: ThreadState
    var draft = ""
    let interactions: MessageInteractions

    @ObservationIgnored let data: DataEnvironment?
    @ObservationIgnored let clock: ChatClock
    @ObservationIgnored let platform: ChatPlatform
    @ObservationIgnored let context: ChatContext
    @ObservationIgnored var thread = Resource<ThreadTimeline>()
    @ObservationIgnored var allMessages: [ChatMessage] = []
    @ObservationIgnored var isVisible = false
    @ObservationIgnored var lastMarkedRead: Int?
    @ObservationIgnored var sendTracker = SendTracker()
    @ObservationIgnored var arrivalTracker = ArrivalTracker()
    @ObservationIgnored var liveArrivals: Set<String> = []
    @ObservationIgnored let richCache = RichDocumentCache()
    @ObservationIgnored var highlightRequested = false
    @ObservationIgnored var nextScrollId = 0

    init(
        rootMessageID: Int,
        conversationID: Int?,
        targetMessageID: Int?,
        data: DataEnvironment?,
        clock: ChatClock = ChatClock(),
        platform: ChatPlatform = ChatPlatform()
    ) {
        self.rootMessageID = rootMessageID
        self.conversationID = conversationID
        self.targetMessageID = targetMessageID
        self.data = data
        self.clock = clock
        self.platform = platform
        let valid = rootMessageID > 0 && (conversationID ?? 0) > 0
        state = ThreadState(content: valid ? .loading : .invalid)
        let context = ChatContext(conversationId: conversationID ?? 0)
        self.context = context
        interactions = MessageInteractions(
            conversationId: conversationID ?? 0,
            actions: data?.threads,
            bookmarks: data?.bookmarks,
            attachments: data?.attachments,
            platform: platform,
            isConnected: { context.isConnected },
            wait: { try? await clock.sleep(seconds: $0) }
        )
    }

    /// A model that only displays `state`, for previews and snapshot tests.
    convenience init(preview: ThreadState, draft: String = "", clock: ChatClock = ChatClock()) {
        self.init(rootMessageID: 9330, conversationID: 7, targetMessageID: nil, data: nil, clock: clock)
        state = preview
        self.draft = draft
    }

    var isValid: Bool { rootMessageID > 0 && (conversationID ?? 0) > 0 }

    // MARK: Lifecycle

    func run() async {
        guard isValid, let data, let conversationId = conversationID else { return }
        isVisible = true
        lastMarkedRead = nil
        let rootId = rootMessageID
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.context.run(data) { change in self.contextChanged(change) } }
            group.addTask { await self.observeThread(data, conversationId: conversationId) }
            group.addTask { await data.threads.open(rootMessageId: rootId, conversationId: conversationId) }
            group.addTask { await self.highlightTargetIfNeeded() }
        }
        isVisible = false
        await data.threads.close(rootMessageId: rootId, conversationId: conversationId)
    }

    private func observeThread(_ data: DataEnvironment, conversationId: Int) async {
        for await resource in data.threads.thread(rootMessageId: rootMessageID, conversationId: conversationId) {
            thread = resource
            rebuild()
        }
    }

    private func contextChanged(_ change: ChatContext.Change) {
        switch change {
        case .conversation:
            guard let conversation = context.conversation else { return }
            state.conversationTitle = conversation.title
            state.canWrite = WritePermission.canWrite(conversation)
            state.readOnlyReason = ReadOnlyReason.thread(conversation)
            rebuild()
        case .viewer, .bookmarks: rebuild()
        case .names: state.names = context.names(messages: allMessages)
        case .subtitle: state.subtitle = context.subtitle
        }
    }

    // MARK: State

    private func rebuild() {
        guard isValid else { return }
        let value = thread.value
        let root = value?.root.map(context.marked)
        let replies = (value?.replies ?? []).map(context.marked)
        let pending = value?.pending ?? []
        allMessages = [root].compactMap { $0 } + replies
        if value != nil {
            trackArrivals(replies: replies, pending: pending)
            trackSends(pending)
        }
        var next = state
        next.root = buildRoot(root)
        next.replies = TimelineBuilder.build(
            TimelineInput(
                messages: replies,
                pending: pending,
                viewerId: context.viewerId,
                zone: clock.timeZone,
                botConversation: context.conversation?.kind == .bot,
                liveArrivals: liveArrivals
            ),
            richDocument: richCache.document(for:)
        )
        next.replyCount = replies.count
        let hasData = root != nil || !replies.isEmpty || !pending.isEmpty
        next.content = Self.content(hasData: hasData, thread: thread)
        next.isStale = hasData && thread.error != nil
        next.viewerId = context.viewerId
        next.names = context.names(messages: allMessages)
        if next != state { state = next }
        markReadIfNeeded()
    }

    private func buildRoot(_ root: ChatMessage?) -> MessageRow? {
        guard let root else { return nil }
        let items = TimelineBuilder.build(
            TimelineInput(
                messages: [root],
                viewerId: context.viewerId,
                zone: clock.timeZone,
                botConversation: context.conversation?.kind == .bot,
                daySeparators: false
            ),
            richDocument: richCache.document(for:)
        )
        guard case .message(let row) = items.first else { return nil }
        return row
    }

    private static func content(hasData: Bool, thread: Resource<ThreadTimeline>) -> ThreadContent {
        if hasData { return .ready }
        if let error = thread.error { return .error(error) }
        return thread.phase == .loaded ? .ready : .loading
    }

    private func trackArrivals(replies: [ChatMessage], pending: [OutgoingMessage]) {
        let entries = ArrivalTracker.entries(messages: replies, pending: pending)
        let arrivals = arrivalTracker.update(entries)
        guard !arrivals.isEmpty else { return }
        // Someone else's reply landing in the open thread is silent, as on the timeline.
        liveArrivals.formUnion(arrivals)
        let clock = clock
        Task { [weak self] in
            try? await clock.sleep(seconds: ConversationModel.arrivalWindow)
            self?.liveArrivals.subtract(arrivals)
            self?.rebuild()
        }
    }

    private func trackSends(_ pending: [OutgoingMessage]) {
        let events = sendTracker.update(pending)
        if let failure = events.newFailures.last {
            state.sendError = SendErrorKind(failure)
            platform.haptic(.sendFailed)
        }
    }

    /// 04 §4: read-through with the thread root whenever the newest reply changes.
    private func markReadIfNeeded() {
        guard isVisible, let data, let conversationId = conversationID,
            let newest = allMessages.last(where: { $0.id > 0 })?.id,
            newest != lastMarkedRead
        else { return }
        lastMarkedRead = newest
        let rootId = rootMessageID
        Task { await data.threads.markRead(rootMessageId: rootId, conversationId: conversationId) }
    }

    func retryLoad() async {
        guard let data, let conversationId = conversationID else { return }
        if context.conversation == nil { await context.loadDetail(data) { self.contextChanged($0) } }
        await data.threads.refresh(rootMessageId: rootMessageID, conversationId: conversationId)
    }

    // MARK: Highlight (04 §5)

    /// Highlights only what the thread response holds; no context fetch and no error.
    func highlightTargetIfNeeded() async {
        guard let target = targetMessageID, target > 0, !highlightRequested else { return }
        highlightRequested = true
        while state.content == .loading {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return
            }
        }
        guard let key = keyFor(target) else { return }
        try? await clock.sleep(seconds: Self.highlightScrollDelay)
        nextScrollId += 1
        state.scrollCommand = ScrollCommand(id: nextScrollId, target: .key(key))
        state.highlightKey = key
        try? await clock.sleep(seconds: ConversationModel.highlightDuration)
        if state.highlightKey == key { state.highlightKey = nil }
    }

    func keyFor(_ messageId: Int) -> String? {
        if let root = state.root, root.message.id == messageId { return root.key }
        return state.replies.first { $0.message(messageId) != nil }?.id
    }
}

enum ThreadContent: Equatable, Sendable {
    /// The route's ids can never be a thread (04 §8: rejected locally, no request).
    case invalid
    case loading
    case error(WaiveraError)
    /// Loaded; `root` is `nil` when the original message is gone.
    case ready
}

/// Everything the thread screen draws.
struct ThreadState: Equatable, Sendable {
    var subtitle: ConnectionSubtitle?
    var content: ThreadContent = .loading
    var root: MessageRow?
    /// Replies oldest first, with day separators.
    var replies: [TimelineItem] = []
    var replyCount = 0
    var isStale = false
    var highlightKey: String?
    var visibleTimestamps: Set<String> = []
    var names: [String: String] = [:]
    var conversationTitle: ConversationTitle?
    var canWrite: Bool?
    var readOnlyReason: ReadOnlyReason?
    var sendError: SendErrorKind?
    var editingMessageID: Int?
    var scrollCommand: ScrollCommand?
    /// Bumped to move focus into the reply box (Reply on the action sheet).
    var focusRequest = 0
    var viewerId: String?
}
