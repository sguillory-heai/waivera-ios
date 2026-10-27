import Foundation
import WaiveraAPI
import WaiveraRealtime

/// A scripted chat hub. Tests and the demo app connect it, drop it, emit events now or play
/// a script on the fake clock; every client call is recorded. Sends echo the message back
/// with the client id, like sprout_api.
public final class FakeRealtimeClient: RealtimeClient, @unchecked Sendable {
    /// One step of a script: wait `after` on the clock, then deliver `event`.
    public struct ScriptedEvent: Sendable {
        public var after: Duration
        public var event: ChatHubEvent

        public init(after: Duration = .zero, _ event: ChatHubEvent) {
            self.after = after
            self.event = event
        }
    }

    public struct Log: Sendable {
        public var starts = 0
        public var stops = 0
        public var retries = 0
        public var joins: [Int] = []
        public var leaves: [Int] = []
        public var sent: [HubSendMessage] = []
        public var markedRead: [Int] = []
        public var reactions: [String] = []
        public var typing: [String] = []
    }

    private let clock: any WaiveraClock
    private let statusBroadcaster = AsyncBroadcaster(initial: RealtimeStatus.initial)
    private let eventBroadcaster = AsyncBroadcaster<ChatHubEvent>(replays: false)
    private let status = LockedValue(RealtimeStatus.initial)
    private let state = LockedValue(Log())
    private let nextId = LockedValue(30_000)
    /// When true, `start()` connects at once (the demo app); tests usually connect by hand.
    public let connectsOnStart: Bool
    /// The failure `SendMessage` and `SendReaction` throw, if any.
    public let invocationFailure = LockedValue<WaiveraError?>(nil)

    public init(clock: any WaiveraClock, connectsOnStart: Bool = false) {
        self.clock = clock
        self.connectsOnStart = connectsOnStart
    }

    public var log: Log { state.get() }

    public func statuses() -> AsyncStream<RealtimeStatus> { statusBroadcaster.stream() }
    public var currentStatus: RealtimeStatus { status.get() }
    public func events() -> AsyncStream<ChatHubEvent> { eventBroadcaster.stream() }

    // MARK: Script controls

    public func connect() {
        publish { $0 = RealtimeStatus(state: .connected, epoch: $0.epoch + 1) }
    }

    public func drop(attempt: Int = 1) {
        publish { $0.state = .reconnecting(attempt: attempt, delay: .seconds(1 << min(attempt, 5))) }
    }

    public func emit(_ event: ChatHubEvent) { eventBroadcaster.send(event) }

    /// Plays `script` in order on the clock; cancel the returned task to stop it.
    @discardableResult
    public func play(_ script: [ScriptedEvent]) -> Task<Void, Never> {
        let clock = clock
        return Task {
            for step in script {
                if step.after > .zero {
                    do { try await clock.sleep(for: step.after) } catch { return }
                }
                self.emit(step.event)
            }
        }
    }

    private func publish(_ change: (inout RealtimeStatus) -> Void) {
        let next = status.update { value -> RealtimeStatus in
            change(&value)
            return value
        }
        statusBroadcaster.send(next)
    }

    // MARK: RealtimeClient

    public func start() async {
        state.update { $0.starts += 1 }
        if connectsOnStart { connect() }
    }

    public func stop() async {
        state.update { $0.stops += 1 }
        publish { $0.state = .disconnected }
    }

    public func setForeground(_ isForeground: Bool) async {
        guard connectsOnStart, state.get().starts > state.get().stops else { return }
        if isForeground { connect() } else { publish { $0.state = .disconnected } }
    }

    public func setNetworkAvailable(_ isAvailable: Bool) async {
        if isAvailable, connectsOnStart, !currentStatus.isConnected { connect() }
        if !isAvailable { publish { $0.state = .disconnected } }
    }

    public func retryNow() async {
        state.update { $0.retries += 1 }
        connect()
    }

    public func join(conversationId: Int) async { state.update { $0.joins.append(conversationId) } }
    public func leave(conversationId: Int) async { state.update { $0.leaves.append(conversationId) } }

    public func sendMessage(_ message: HubSendMessage) async throws -> MessageSendResponse {
        guard currentStatus.isConnected else { throw WaiveraError.realtimeUnavailable }
        if let failure = invocationFailure.get() { throw failure }
        state.update { $0.sent.append(message) }
        let id = nextId.update { value -> Int in
            value += 1
            return value
        }
        var response = MessageSendResponse(id: id, conversationId: message.conversationId)
        response.clientMessageId = message.clientMessageId
        response.messageContent = message.text
        response.messageDoc = message.doc
        response.parentMessageId = message.parentMessageId
        response.threadRootMessageId = message.parentMessageId
        response.attachmentUrl = message.attachmentUrl
        response.userId = DemoData.viewerId
        response.createDate = clock.now
        return response
    }

    public func sendTypingStatus(conversationId: Int, isTyping: Bool) async {
        state.update { $0.typing.append("\(conversationId):\(isTyping)") }
    }

    public func markAsRead(conversationId: Int) async throws {
        guard currentStatus.isConnected else { throw WaiveraError.realtimeUnavailable }
        state.update { $0.markedRead.append(conversationId) }
    }

    public func sendReaction(messageId: Int, reactionType: String) async throws {
        guard currentStatus.isConnected else { throw WaiveraError.realtimeUnavailable }
        if let failure = invocationFailure.get() { throw failure }
        state.update { $0.reactions.append("\(messageId):\(reactionType)") }
    }
}
