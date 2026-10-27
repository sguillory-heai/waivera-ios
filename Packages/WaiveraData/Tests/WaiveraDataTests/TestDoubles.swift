import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

let viewerId = "usr_alex_rivera"
let testBaseURL = URL(string: "https://api.example.test/") ?? URL(filePath: "/")

/// Answers requests by `"METHOD path"`: queued replies first, then the route's standing reply,
/// else 404. Records every request.
actor RoutingTransport: HTTPTransport {
    struct Reply: Sendable {
        var status: Int
        var body: Data

        static func json(_ text: String, status: Int = 200) -> Reply { Reply(status: status, body: Data(text.utf8)) }
        static func fixture(_ name: String, status: Int = 200) -> Reply {
            Reply(status: status, body: (try? Fixture.data(name)) ?? Data())
        }
        static func status(_ status: Int, _ body: String = "") -> Reply { Reply(status: status, body: Data(body.utf8)) }
        static let ok = Reply(status: 200, body: Data())
    }

    private var standing: [String: Reply] = [:]
    private var queued: [String: [Reply]] = [:]
    private(set) var requests: [URLRequest] = []
    var isOffline = false

    func set(_ route: String, _ reply: Reply) { standing[route] = reply }
    func enqueue(_ route: String, _ replies: Reply...) { queued[route, default: []] += replies }
    func setOffline(_ offline: Bool) { isOffline = offline }

    func count(_ route: String) -> Int { requests.filter { Self.route(of: $0) == route }.count }

    func bodies(_ route: String) -> [Data] {
        requests.filter { Self.route(of: $0) == route }.compactMap(\.httpBody)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if isOffline { throw URLError(.notConnectedToInternet) }
        let route = Self.route(of: request)
        let reply: Reply
        if var pending = queued[route], !pending.isEmpty {
            reply = pending.removeFirst()
            queued[route] = pending
        } else {
            reply = standing[route] ?? .status(404, "Not found")
        }
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badURL) }
        return (reply.body, response)
    }

    static func route(of request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return "\(request.httpMethod ?? "GET") \(path.drop { $0 == "/" })"
    }
}

/// Signed in with a fixed token unless told otherwise.
final class FakeAuth: AuthSession, @unchecked Sendable {
    private let cell: StateCell<FirebaseIdentity?>
    private let log = LockedValue<[String]>([])

    init(signedIn: Bool = true) {
        cell = StateCell(
            signedIn ? FirebaseIdentity(uid: "fb-alex", email: "alex.rivera@example.com", displayName: nil) : nil
        )
    }

    var calls: [String] { log.get() }

    func identities() -> AsyncStream<FirebaseIdentity?> { cell.stream() }

    func idToken(forceRefresh: Bool) async throws -> String? {
        cell.current == nil ? nil : "token"
    }

    func signIn(email: String, password: String) async throws -> FirebaseIdentity {
        log.update { $0.append("signIn") }
        guard password == "correct" else { throw WaiveraError.auth(.invalidCredentials) }
        let identity = FirebaseIdentity(uid: "fb-alex", email: email, displayName: nil)
        cell.set(identity)
        return identity
    }

    func changePassword(current: String, new: String) async throws {
        log.update { $0.append("changePassword") }
    }

    func signOut() async {
        log.update { $0.append("signOut") }
        cell.set(nil)
    }

    /// Simulates a token refresh: same identity emitted again.
    func emitSameIdentity() {
        cell.set(cell.current)
    }
}

/// A scripted hub: tests connect, disconnect and emit events; client calls are recorded.
final class FakeRealtime: RealtimeClient, @unchecked Sendable {
    struct Log: Sendable {
        var joins: [Int] = []
        var leaves: [Int] = []
        var sent: [HubSendMessage] = []
        var markAsRead: [Int] = []
        var reactions: [(Int, String)] = []
        var typing: [(Int, Bool)] = []
        var starts = 0
        var stops = 0
    }

    private let statusCell = StateCell(RealtimeStatus.initial)
    private let eventBroadcaster = AsyncBroadcaster<ChatHubEvent>(replays: false)
    private let state = LockedValue(Log())
    /// Result for `SendMessage`; default echoes the message with id 10_000 + n.
    let sendResult = LockedValue<(@Sendable (HubSendMessage) throws -> MessageSendResponse)?>(nil)
    let reactionError = LockedValue<WaiveraError?>(nil)

    var log: Log { state.get() }

    func statuses() -> AsyncStream<RealtimeStatus> { statusCell.stream() }
    var currentStatus: RealtimeStatus { statusCell.current }
    func events() -> AsyncStream<ChatHubEvent> { eventBroadcaster.stream() }

    func connect() {
        statusCell.update { $0 = RealtimeStatus(state: .connected, epoch: $0.epoch + 1) }
    }

    func drop() {
        statusCell.update { $0.state = .reconnecting(attempt: 1, delay: .zero) }
    }

    func emit(_ event: ChatHubEvent) { eventBroadcaster.send(event) }

    func start() async { state.update { $0.starts += 1 } }
    func stop() async {
        state.update { $0.stops += 1 }
        statusCell.update { $0.state = .disconnected }
    }
    func setForeground(_ isForeground: Bool) async {}
    func setNetworkAvailable(_ isAvailable: Bool) async {}
    func retryNow() async {}
    func join(conversationId: Int) async { state.update { $0.joins.append(conversationId) } }
    func leave(conversationId: Int) async { state.update { $0.leaves.append(conversationId) } }

    func sendMessage(_ message: HubSendMessage) async throws -> MessageSendResponse {
        guard currentStatus.isConnected else { throw WaiveraError.realtimeUnavailable }
        let count = state.update { log -> Int in
            log.sent.append(message)
            return log.sent.count
        }
        if let handler = sendResult.get() { return try handler(message) }
        var response = MessageSendResponse(id: 10_000 + count, conversationId: message.conversationId)
        response.clientMessageId = message.clientMessageId
        response.messageContent = message.text
        response.userId = viewerId
        response.parentMessageId = message.parentMessageId
        // After every fixture timestamp, like a fresh server write.
        response.createDate = Date(timeIntervalSince1970: 1_792_600_000)
        return response
    }

    func sendTypingStatus(conversationId: Int, isTyping: Bool) async {
        state.update { $0.typing.append((conversationId, isTyping)) }
    }

    func markAsRead(conversationId: Int) async throws {
        guard currentStatus.isConnected else { throw WaiveraError.realtimeUnavailable }
        state.update { $0.markAsRead.append(conversationId) }
    }

    func sendReaction(messageId: Int, reactionType: String) async throws {
        state.update { $0.reactions.append((messageId, reactionType)) }
        if let error = reactionError.get() { throw error }
    }
}

/// Time moves only when a test advances it; sleepers wake when their deadline passes.
final class TestClock: WaiveraClock, @unchecked Sendable {
    private struct Sleeper {
        var deadline: Date
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Date
        var sleepers: [UUID: Sleeper] = [:]
    }

    private let state: LockedValue<State>

    init(_ start: Date = Date(timeIntervalSince1970: 1_792_500_000)) {
        state = LockedValue(State(now: start))
    }

    var now: Date { state.get().now }
    var pendingSleepers: Int { state.get().sleepers.count }

    func sleep(for duration: Duration) async throws {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        guard seconds > 0 else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let fireNow = state.update { state -> Bool in
                    if Task.isCancelled { return true }
                    state.sleepers[id] = Sleeper(
                        deadline: state.now.addingTimeInterval(seconds),
                        continuation: continuation
                    )
                    return false
                }
                if fireNow { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let sleeper = state.update { $0.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes due sleepers, then lets woken tasks run.
    func advance(by seconds: TimeInterval) async {
        let due = state.update { state -> [Sleeper] in
            state.now = state.now.addingTimeInterval(seconds)
            let ready = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in ready.keys { state.sleepers[id] = nil }
            return Array(ready.values)
        }
        for sleeper in due { sleeper.continuation.resume() }
        await settle()
    }
}

/// Lets queued tasks run; actors and detached work in these tests finish within a few hops.
func settle(_ rounds: Int = 30) async {
    for _ in 0..<rounds { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(5))
    for _ in 0..<rounds { await Task.yield() }
}

/// Polls `condition` for up to ~2 s of real time.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

let alex = CurrentUser(
    id: viewerId,
    firebaseUid: "fb-alex",
    email: "alex.rivera@example.com",
    firstName: "Alex",
    lastName: "Rivera",
    timeZoneIdentifier: "America/Chicago"
)

/// A chat engine over a routing transport and a fake hub.
struct ChatHarness {
    let transport = RoutingTransport()
    let realtime = FakeRealtime()
    let store = InMemoryLocalStore()
    let clock = TestClock()
    let presence = ChatPresence()
    let engine: ChatEngine

    init() {
        let api = APIClient(baseURL: testBaseURL, transport: transport, tokens: FakeAuth())
        engine = ChatEngine(api: api, realtime: realtime, store: store, clock: clock, presence: presence)
    }

    var api: APIClient { APIClient(baseURL: testBaseURL, transport: transport, tokens: FakeAuth()) }

    func begin() async {
        await engine.begin(user: alex)
    }
}

func decodeFixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try WaiveraJSON.decoder().decode(type, from: Fixture.data(name))
}

func message(
    _ id: Int,
    in conversationId: Int = 7,
    author: String = "usr_priya_raman",
    text: String? = "hello",
    at seconds: TimeInterval = 1_792_400_000,
    parent: Int? = nil,
    clientId: String? = nil
) -> MessageSendResponse {
    var dto = MessageSendResponse(id: id, conversationId: conversationId)
    dto.userId = author
    dto.messageContent = text
    dto.createDate = Date(timeIntervalSince1970: seconds)
    dto.parentMessageId = parent
    dto.threadRootMessageId = parent
    dto.clientMessageId = clientId
    return dto
}

func jsonArray(_ messages: [MessageSendResponse]) -> RoutingTransport.Reply {
    let data = (try? WaiveraJSON.encoder().encode(messages)) ?? Data()
    return RoutingTransport.Reply(status: 200, body: data)
}

let utcZone = TimeZone(secondsFromGMT: 0) ?? .current
let chicago = TimeZone(identifier: "America/Chicago") ?? .current

func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
    CalendarDate(year: year, month: month, day: day) ?? CalendarDate(Date(timeIntervalSince1970: 0), in: utcZone)
}

func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    date(year, month, day).startInstant(in: utcZone).addingTimeInterval(Double(hour * 3_600 + minute * 60))
}

/// Reads the latest value a stream has replayed.
func latest<T: Sendable>(_ stream: AsyncStream<T>) async -> T? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}

func hubEvent(_ fixture: String) throws -> ChatHubEvent {
    let invocation = try WaiveraJSON.decoder().decode(HubInvocation.self, from: Fixture.data(fixture))
    return try #require(HubEventDecoder.decode(invocation))
}

func makeAPI(_ transport: RoutingTransport) -> APIClient {
    APIClient(baseURL: testBaseURL, transport: transport, tokens: FakeAuth())
}
