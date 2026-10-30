import Foundation
import WaiveraAPI

/// `RealtimeClient` over any `HubConnection` transport.
///
/// - Reconnects forever with `ReconnectPolicy` while signed in, foregrounded and online (fixes
///   the Expo four-attempt cap, 11 §2.11); `retryNow()` skips the wait.
/// - Rejoins every desired conversation group on each connect and bumps `epoch` so
///   repositories resync over REST (05 §2).
/// - The first attempt after a long background, and the first retry after the hub rejected the
///   token, use a force-refreshed token. Other failures (a hub outage, the network) reuse the
///   current token, which the provider still refreshes near expiry, so an outage never turns
///   into a stream of forced refreshes that Firebase rate-limits (IS-02).
public actor LiveRealtimeClient: RealtimeClient {
    /// A background longer than this forces a token refresh on the next connect.
    public static let staleTokenInterval: TimeInterval = 300

    private let hubURL: URL
    private let factory: any HubConnectionFactory
    private let tokens: any AuthTokenProvider
    private let policy: ReconnectPolicy
    private let clock: any WaiveraClock

    private let statusBroadcaster = AsyncBroadcaster(initial: RealtimeStatus.initial)
    private let eventBroadcaster = AsyncBroadcaster<ChatHubEvent>(replays: false, keepsEveryValue: true)
    private let status = LockedValue(RealtimeStatus.initial)

    private var isStarted = false
    private var isForeground = true
    private var isNetworkAvailable = true
    private var backgroundedAt: Date?
    private var forceTokenRefresh = false
    private var generation = 0
    private var loop: Task<Void, Never>?
    private var wakeUp: CheckedContinuation<Void, Never>?
    private var waitID = 0
    private var connection: (any HubConnection)?
    private var groups: [Int: Int] = [:]
    private var deduplicator = MessageDeduplicator()

    public init(
        hubURL: URL,
        factory: any HubConnectionFactory,
        tokens: any AuthTokenProvider,
        policy: ReconnectPolicy = ReconnectPolicy(),
        clock: any WaiveraClock = SystemClock()
    ) {
        self.hubURL = hubURL
        self.factory = factory
        self.tokens = tokens
        self.policy = policy
        self.clock = clock
    }

    nonisolated public func statuses() -> AsyncStream<RealtimeStatus> { statusBroadcaster.stream() }
    nonisolated public var currentStatus: RealtimeStatus { status.get() }
    nonisolated public func events() -> AsyncStream<ChatHubEvent> { eventBroadcaster.stream() }

    // MARK: Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        reconcile()
    }

    public func stop() async {
        isStarted = false
        groups.removeAll()
        deduplicator.reset()
        await tearDown()
    }

    public func setForeground(_ isForeground: Bool) async {
        guard self.isForeground != isForeground else { return }
        self.isForeground = isForeground
        if isForeground {
            if let backgroundedAt, clock.now.timeIntervalSince(backgroundedAt) > Self.staleTokenInterval {
                forceTokenRefresh = true
            }
            backgroundedAt = nil
            reconcile()
        } else {
            backgroundedAt = clock.now
            await tearDown()
        }
    }

    public func setNetworkAvailable(_ isAvailable: Bool) async {
        guard isNetworkAvailable != isAvailable else { return }
        isNetworkAvailable = isAvailable
        if isAvailable {
            reconcile()
            wake()
        } else {
            await tearDown()
        }
    }

    public func retryNow() {
        reconcile()
        wake()
    }

    // MARK: Connection loop

    private var shouldRun: Bool { isStarted && isForeground && isNetworkAvailable }

    private func reconcile() {
        guard shouldRun, loop == nil else { return }
        generation += 1
        let current = generation
        loop = Task { await self.run(generation: current) }
    }

    private func tearDown() async {
        generation += 1
        loop?.cancel()
        loop = nil
        wake()
        let closing = connection
        connection = nil
        publish(.disconnected)
        await closing?.stop()
    }

    private func run(generation current: Int) async {
        var attempt = 0
        while shouldRun, generation == current, !Task.isCancelled {
            attempt += 1
            if attempt > 1 || status.get().epoch > 0 {
                let delay = policy.delay(forAttempt: attempt)
                publish(.reconnecting(attempt: attempt, delay: delay))
                await waitOrWake(delay)
                guard shouldRun, generation == current else { break }
            }
            publish(.connecting)
            if await connectOnce(generation: current) {
                attempt = 0
            }
        }
        if generation == current { loop = nil }
    }

    /// Returns true when the connection was established (and has since closed).
    private func connectOnce(generation current: Int) async -> Bool {
        let refresh = forceTokenRefresh
        let tokens = tokens
        let candidate = factory.makeConnection(
            url: hubURL,
            eventSignatures: ChatHubContract.Event.signatures,
            accessToken: { try await Self.token(from: tokens, forceRefresh: refresh) }
        )
        let pump = Task { await self.pump(candidate.invocations, generation: current) }
        do {
            try await candidate.start()
        } catch {
            pump.cancel()
            // Only a rejected token is worth a forced refresh, and only once in a row: if the hub
            // still says no with a fresh token, the API side ends the session (IF-05).
            forceTokenRefresh = WaiveraError.from(error) == .unauthorized && !refresh
            return false
        }
        guard generation == current, shouldRun else {
            pump.cancel()
            await candidate.stop()
            return false
        }
        forceTokenRefresh = false
        connection = candidate
        await rejoinGroups(on: candidate)
        publish(.connected, bumpEpoch: true)
        _ = await candidate.waitUntilClosed()
        pump.cancel()
        if generation == current {
            connection = nil
        }
        return true
    }

    /// Joins every group, including ones a screen opened while an earlier join was in flight:
    /// `join` skips the hub until the state is connected, so the loop re-reads `groups` after
    /// each call, and nothing suspends between the last check and publishing `.connected`.
    private func rejoinGroups(on connection: any HubConnection) async {
        var joined = Set<Int>()
        while let conversationId = groups.keys.sorted().first(where: { !joined.contains($0) }) {
            joined.insert(conversationId)
            // A failed join is retried on the next connect; the screen still resyncs over REST.
            _ = try? await connection.invoke(
                ChatHubContract.Method.joinConversation,
                arguments: [number(conversationId)]
            )
        }
    }

    private func pump(_ invocations: AsyncStream<HubInvocation>, generation current: Int) async {
        for await invocation in invocations {
            guard generation == current else { return }
            guard let event = HubEventDecoder.decode(invocation) else { continue }
            if case .message(let message) = event, !deduplicator.shouldProcess(message, now: clock.now) { continue }
            if case .conversationListMessage(let message) = event {
                guard deduplicator.shouldProcess(message, now: clock.now) else { continue }
            }
            eventBroadcaster.send(event)
        }
    }

    private func waitOrWake(_ delay: Duration) async {
        guard delay > .zero else { return }
        waitID += 1
        let id = waitID
        let clock = clock
        let sleeper = Task {
            try? await clock.sleep(for: delay)
            self.endWait(id)
        }
        await withCheckedContinuation { continuation in
            wakeUp = continuation
        }
        sleeper.cancel()
    }

    /// Ends the backoff wait only if it is still the one this sleeper was started for.
    private func endWait(_ id: Int) {
        guard id == waitID else { return }
        wake()
    }

    private func wake() {
        wakeUp?.resume()
        wakeUp = nil
    }

    private func publish(_ state: ConnectionState, bumpEpoch: Bool = false) {
        let next = status.update { value -> RealtimeStatus in
            value.state = state
            if bumpEpoch { value.epoch += 1 }
            return value
        }
        statusBroadcaster.send(next)
    }

    private func number(_ value: Int) -> JSONValue { .number(Double(value)) }

    private static func token(from tokens: any AuthTokenProvider, forceRefresh: Bool) async throws -> String {
        guard let token = try await tokens.idToken(forceRefresh: forceRefresh) else {
            throw WaiveraError.signedOut
        }
        return token
    }
}

extension LiveRealtimeClient {
    // MARK: Groups

    public func join(conversationId: Int) async {
        let count = groups[conversationId, default: 0]
        groups[conversationId] = count + 1
        guard count == 0, let connection, status.get().isConnected else { return }
        _ = try? await connection.invoke(ChatHubContract.Method.joinConversation, arguments: [number(conversationId)])
    }

    public func leave(conversationId: Int) async {
        guard let count = groups[conversationId] else { return }
        if count > 1 {
            groups[conversationId] = count - 1
            return
        }
        groups.removeValue(forKey: conversationId)
        guard let connection, status.get().isConnected else { return }
        _ = try? await connection.invoke(ChatHubContract.Method.leaveConversation, arguments: [number(conversationId)])
    }

    // MARK: Client methods

    public func sendMessage(_ message: HubSendMessage) async throws -> MessageSendResponse {
        let result = try await invokeConnected(ChatHubContract.Method.sendMessage, message.arguments)
        do {
            return try result.decode(as: MessageSendResponse.self)
        } catch {
            throw WaiveraError.invalidResponse
        }
    }

    public func sendTypingStatus(conversationId: Int, isTyping: Bool) async {
        guard let connection, status.get().isConnected else { return }
        try? await connection.send(
            ChatHubContract.Method.sendTypingStatus,
            arguments: [number(conversationId), .bool(isTyping)]
        )
    }

    public func markAsRead(conversationId: Int) async throws {
        _ = try await invokeConnected(ChatHubContract.Method.markAsRead, [number(conversationId)])
    }

    public func sendReaction(messageId: Int, reactionType: String) async throws {
        _ = try await invokeConnected(ChatHubContract.Method.sendReaction, [number(messageId), .string(reactionType)])
    }

    fileprivate func invokeConnected(_ method: String, _ arguments: [JSONValue]) async throws -> JSONValue {
        guard let connection, status.get().isConnected else { throw WaiveraError.realtimeUnavailable }
        do {
            return try await connection.invoke(method, arguments: arguments)
        } catch let error as HubInvocationError {
            throw error.waiveraError
        } catch {
            throw WaiveraError.from(error)
        }
    }
}
