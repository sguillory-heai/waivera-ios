import Foundation
import Observation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// One conversation: timeline, composer, typing, read state and the message actions (03,
/// 05 §2-4). Plain Swift over the data layer, so every state is tested on Linux.
@MainActor
@Observable
final class ConversationModel {
    static let arrivalWindow = 1.0
    static let highlightScrollDelay = 0.16
    static let highlightDuration = MotionPolicy.targetHighlightDuration
    static let maxHighlightPages = 8

    let conversationID: Int
    let targetMessageID: Int?
    /// Set only by this model and its extensions.
    var state: ConversationState
    /// The composer text; the view binds it and reports edits through `draftChanged()`.
    var draft = ""
    let interactions: MessageInteractions

    @ObservationIgnored let data: DataEnvironment?
    @ObservationIgnored let clock: ChatClock
    @ObservationIgnored let platform: ChatPlatform
    @ObservationIgnored let onOpenThread: @MainActor (_ rootMessageID: Int, _ targetMessageID: Int?) -> Void
    @ObservationIgnored let context: ChatContext
    @ObservationIgnored var timeline = Resource<MessageTimeline>()
    @ObservationIgnored var typingIds: [String] = []
    @ObservationIgnored var isVisible = false
    @ObservationIgnored var lastMarkedRead: Int?
    @ObservationIgnored var sendTracker = SendTracker()
    @ObservationIgnored var arrivalTracker = ArrivalTracker()
    @ObservationIgnored var liveArrivals: Set<String> = []
    @ObservationIgnored let richCache = RichDocumentCache()
    @ObservationIgnored var highlightRequested = false
    @ObservationIgnored var nextScrollId = 0
    @ObservationIgnored var rebuildCount = 0

    // swiftlint:disable:next function_parameter_count
    init(
        conversationID: Int,
        targetMessageID: Int?,
        data: DataEnvironment?,
        clock: ChatClock = ChatClock(),
        platform: ChatPlatform = ChatPlatform(),
        onOpenThread: @escaping @MainActor (_ rootMessageID: Int, _ targetMessageID: Int?) -> Void = { _, _ in }
    ) {
        self.conversationID = conversationID
        self.targetMessageID = targetMessageID
        self.data = data
        self.clock = clock
        self.platform = platform
        self.onOpenThread = onOpenThread
        state = ConversationState(content: conversationID > 0 ? .loading : .invalid)
        let context = ChatContext(conversationId: conversationID)
        self.context = context
        interactions = MessageInteractions(
            conversationId: conversationID,
            actions: data?.messages,
            bookmarks: data?.bookmarks,
            attachments: data?.attachments,
            platform: platform,
            isConnected: { context.isConnected }
        )
    }

    /// A model that only displays `state`, for previews and snapshot tests.
    convenience init(preview: ConversationState, draft: String = "", clock: ChatClock = ChatClock()) {
        self.init(conversationID: 7, targetMessageID: nil, data: nil, clock: clock)
        state = preview
        self.draft = draft
    }

    var isValid: Bool { conversationID > 0 }

    // MARK: Lifecycle

    /// Runs while the screen is visible (`.task`): joins the hub group, loads and observes.
    /// Cancelling it closes the conversation.
    func run() async {
        guard isValid, let data else { return }
        isVisible = true
        lastMarkedRead = nil
        let id = conversationID
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.context.run(data) { change in self.contextChanged(change) } }
            group.addTask { await self.observeTimeline(data) }
            group.addTask { await self.observeTyping(data) }
            group.addTask { await data.messages.open(conversationId: id) }
            group.addTask { await self.highlightTargetIfNeeded() }
        }
        isVisible = false
        await data.messages.composerChanged(conversationId: id, text: "")
        await data.messages.close(conversationId: id)
    }

    private func observeTimeline(_ data: DataEnvironment) async {
        for await resource in data.messages.timeline(conversationId: conversationID) {
            timeline = resource
            rebuild()
        }
    }

    private func observeTyping(_ data: DataEnvironment) async {
        for await typing in data.conversations.typing() {
            typingIds = typing[conversationID] ?? []
            refreshTyping()
        }
    }

    private func contextChanged(_ change: ChatContext.Change) {
        switch change {
        case .conversation: applyConversation()
        case .viewer, .bookmarks: rebuild()
        case .names: refreshNames()
        case .subtitle: state.subtitle = context.subtitle
        }
    }

    // MARK: State

    private func applyConversation() {
        guard let conversation = context.conversation else { return }
        state.title = conversation.title
        state.isBotConversation = conversation.kind == .bot
        state.canWrite = WritePermission.canWrite(conversation)
        state.readOnlyReason = ReadOnlyReason.conversation(conversation)
        state.call.isAvailable = conversation.kind != .bot
        state.call.isLive = conversation.activeCall != nil
        rebuild()
    }

    private func refreshNames() {
        let names = context.names(messages: timeline.value?.messages ?? [])
        if names != state.names { state.names = names }
        refreshTyping()
    }

    private func refreshTyping() {
        let label = TypingLabel(userIds: typingIds.filter { $0 != context.viewerId }, names: state.names)
        if label != state.typing { state.typing = label }
    }

    /// Runs once per data emission, so the trackers see each change exactly once.
    private func rebuild() {
        guard isValid else { return }
        let value = timeline.value
        let messages = (value?.messages ?? []).filter { !$0.isThreadReply }.map(context.marked)
        let pending = (value?.pending ?? []).filter { $0.parentMessageId == nil }
        // The trackers start from the first real emission, so rows already failed on open keep
        // their inline Retry without raising the banner.
        if value != nil {
            trackArrivals(messages: messages, pending: pending)
            trackSends(pending)
        }
        let richCache = richCache
        let built = TimelineBuilder.build(
            TimelineInput(
                messages: messages,
                pending: pending,
                viewerId: context.viewerId,
                zone: clock.timeZone,
                botConversation: state.isBotConversation,
                liveArrivals: liveArrivals
            ),
            richDocument: richCache.document(for:)
        )
        var next = state
        next.items = built
        next.content = Self.content(built: built, timeline: timeline)
        next.isStale = !built.isEmpty && timeline.error != nil
        next.hasOlder = value?.hasOlder ?? false
        next.isLoadingOlder = value?.isLoadingOlder ?? false
        next.olderFailed = value?.olderPageError != nil
        next.viewerId = context.viewerId
        next.names = context.names(messages: value?.messages ?? [])
        if next != state { state = next }
        refreshTyping()
        rebuildCount += 1
        markReadIfNeeded()
    }

    private static func content(built: [TimelineItem], timeline: Resource<MessageTimeline>) -> ConversationContent {
        if !built.isEmpty { return .messages }
        if let error = timeline.error { return .error(error) }
        return timeline.phase == .loaded ? .empty : .loading
    }

    private func trackArrivals(messages: [ChatMessage], pending: [OutgoingMessage]) {
        let entries = ArrivalTracker.entries(messages: messages, pending: pending)
        let arrivals = arrivalTracker.update(entries)
        guard !arrivals.isEmpty else { return }
        liveArrivals.formUnion(arrivals)
        // Someone else's message landing on screen; the design system decides how it feels.
        if isVisible, zip(messages, entries).contains(where: { !$0.0.isMine && arrivals.contains($0.1.key) }) {
            platform.haptic(.messageReceivedWhileVisible)
        }
        let clock = clock
        Task { [weak self] in
            try? await clock.sleep(seconds: Self.arrivalWindow)
            self?.liveArrivals.subtract(arrivals)
            self?.rebuild()
        }
    }

    private func trackSends(_ pending: [OutgoingMessage]) {
        let events = sendTracker.update(pending)
        if let failure = events.newFailures.last {
            state.sendError = SendErrorKind(failure)
            platform.haptic(.failure)
        }
        if events.retrySucceeded { platform.haptic(.success) }
    }

    /// Mark-as-read plus read-through whenever the newest message changes while the screen is
    /// visible (03 §12). The data layer sends read-through once per message and releases its
    /// guard on failure, so a later change or the next visit retries.
    private func markReadIfNeeded() {
        guard isVisible, let data,
            let newest = state.items.reversed().lazy.compactMap(\.newestServerMessageId).first,
            newest != lastMarkedRead
        else { return }
        lastMarkedRead = newest
        let id = conversationID
        Task { try? await data.messages.markRead(conversationId: id) }
    }

    // MARK: Loading

    func retryLoad() async {
        guard let data else { return }
        if context.conversation == nil { await context.loadDetail(data) { self.contextChanged($0) } }
        await data.messages.refresh(conversationId: conversationID)
    }

    /// Called when the list reaches its oldest row.
    func loadOlder() async {
        guard let data, state.hasOlder, !state.isLoadingOlder else { return }
        state.isLoadingOlder = true
        await data.messages.loadOlder(conversationId: conversationID)
        state.isLoadingOlder = timeline.value?.isLoadingOlder ?? false
    }

    // MARK: Highlight (03 §9)

    /// Scrolls to and briefly highlights the deep-linked message. The data layer loads the
    /// window around it in one call; if that fails, older pages load until the target appears,
    /// at most eight.
    func highlightTargetIfNeeded() async {
        guard let target = targetMessageID, target > 0, !highlightRequested else { return }
        highlightRequested = true
        guard await waitUntil({ self.state.content != .loading }) else { return }
        var key = keyFor(target)
        if key == nil, let data {
            let before = rebuildCount
            let loaded =
                (try? await data.messages.loadAround(conversationId: conversationID, messageId: target)) ?? false
            if loaded {
                _ = await waitUntil({ self.rebuildCount != before && self.keyFor(target) != nil }, timeout: 2)
                key = keyFor(target)
            }
        }
        var pages = 0
        while key == nil, pages < Self.maxHighlightPages, state.hasOlder, let data {
            let before = rebuildCount
            await data.messages.loadOlder(conversationId: conversationID)
            _ = await waitUntil({ self.rebuildCount != before }, timeout: 2)
            key = keyFor(target)
            pages += 1
        }
        guard let key else { return }
        try? await clock.sleep(seconds: Self.highlightScrollDelay)
        scroll(to: .key(key))
        state.highlightKey = key
        try? await clock.sleep(seconds: Self.highlightDuration)
        if state.highlightKey == key { state.highlightKey = nil }
    }

    func keyFor(_ messageId: Int) -> String? {
        state.items.first { $0.contains(messageId: messageId) }?.id
    }

    /// Polls on real time, so it works with a manual test clock too. `false` when cancelled or
    /// timed out.
    func waitUntil(_ condition: @MainActor () -> Bool, timeout: Double = 30) async -> Bool {
        var waited = 0.0
        while !condition() {
            guard waited < timeout else { return false }
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return false
            }
            waited += 0.02
        }
        return true
    }

    func scroll(to target: ScrollCommand.Target) {
        nextScrollId += 1
        state.scrollCommand = ScrollCommand(id: nextScrollId, target: target)
    }

}

extension StagedImage {
    static let defaultFileName = "image.jpg"
}
