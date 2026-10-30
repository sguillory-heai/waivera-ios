import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ChatFeature

/// English copy for the rules under test, so assertions read like the spec.
struct EnglishText: ChatListText {
    let noMessages = "No messages yet"
    let photo = "Photo"
    let fileAttachment = "File attachment"
    let conversationUpdate = "Conversation update"
    let deletedMessage = "Message deleted"
    let channelFallback = "Channel"
    let conversationFallback = "Conversation"
    let botTitle = "Waivera"
    let unknownPerson = "Unknown"
    let you = "You"
    let someone = "Someone"
    let severalTyping = "Several people are typing…"
    let now = "Now"
    let yesterday = "Yesterday"
    let callInProgress = "Call in progress · Join"
    let notSent = "Not sent"

    func groupTitle(first: String, others: Int) -> String {
        "\(first) & \(others) \(others == 1 ? "other" : "others")"
    }

    func compactGroupCount(_ others: Int) -> String { "+\(others)" }

    func typing(name: String) -> String { "\(name) is typing…" }
    func minutesAgo(_ minutes: Int) -> String { "\(minutes)m" }
    func senderPreview(sender: String, preview: String) -> String { "\(sender): \(preview)" }
    func unreadCount(_ count: Int) -> String { "\(count) unread" }
}

/// Polls `condition` on the main actor until it holds or five seconds pass. Streams deliver on
/// their own tasks, so state settles a few hops after a fake changes.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Lets queued main-actor work run without waiting for a condition.
@MainActor
func settle() async {
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(30))
}

enum Sample {
    static let viewer = DemoData.viewerId

    /// A conversation through the production mapper, from a REST-shaped JSON object.
    static func conversation(_ json: String, viewerId: String = viewer) -> Conversation {
        let dto = try? WaiveraJSON.decoder().decode(ConversationResponse.self, from: Data(json.utf8))
        guard let dto, let conversation = ChatMapper(viewerId: viewerId).conversation(dto) else {
            Issue.record("Could not map \(json)")
            return Conversation(id: 0, kind: .direct, viewerId: viewerId)
        }
        return conversation
    }

    static func user(_ id: String, _ first: String, _ last: String) -> String {
        #"{"id": "\#(id)", "firstName": "\#(first)", "lastName": "\#(last)"}"#
    }

    static let me = user(viewer, "Alex", "Rivera")
    static let priya = user("usr_priya_raman", "Priya", "Raman")
    static let jordan = user("usr_jordan_lee", "Jordan", "Lee")
    static let sam = user("usr_sam_ortiz", "Sam", "Ortiz")

    static func message(
        id: Int,
        conversationId: Int,
        authorId: String = "usr_priya_raman",
        text: String = "hello",
        at date: Date = DemoData.now
    ) -> ChatMessage {
        var message = ChatMessage(id: id, conversationId: conversationId, isMine: authorId == viewer, createdAt: date)
        message.authorId = authorId
        message.plaintext = text
        return message
    }
}

/// An inbox the test drives directly: any value, a scripted refresh result, a failing or
/// conflicting create.
final class StubConversations: ConversationsRepository {
    let cell = StateCell(Resource<[Conversation]>())
    let typingCell = StateCell<[Int: [String]]>([:])
    let calls = CallLog()
    /// What the next `refresh()` publishes; `nil` leaves the value and marks it loaded.
    let afterRefresh = LockedValue<[Conversation]?>(nil)
    let createFailure = LockedValue<WaiveraError?>(nil)
    let createdId = LockedValue(9_000)
    private let clock: any WaiveraClock

    init(_ rows: [Conversation]? = nil, updatedAt: Date? = nil, phase: ResourcePhase = .loaded, clock: any WaiveraClock)
    {
        self.clock = clock
        cell.set(Resource(value: rows, phase: phase, updatedAt: updatedAt))
    }

    func conversations() -> AsyncStream<Resource<[Conversation]>> { cell.stream() }
    func typing() -> AsyncStream<[Int: [String]]> { typingCell.stream() }
    func totalUnread() -> AsyncStream<Int> { StateCell(0).stream() }

    func refresh() async {
        calls.record("refresh")
        let next = afterRefresh.get()
        let now = clock.now
        cell.update { resource in
            if let next { resource.value = next }
            resource.phase = .loaded
            resource.updatedAt = now
        }
    }

    func conversation(id: Int) async throws -> Conversation {
        guard let row = cell.current.value?.first(where: { $0.id == id }) else { throw WaiveraError.notFound }
        return row
    }

    func openDirectConversation(with userId: String) async throws -> Conversation {
        calls.record("openDirect:\(userId)")
        throw WaiveraError.notFound
    }

    func createConversation(participantIds: [String]) async throws -> Conversation {
        calls.record("create:\(participantIds.joined(separator: ","))")
        if let failure = createFailure.get() { throw failure }
        return Conversation(id: createdId.get(), kind: .direct, viewerId: Sample.viewer)
    }

    func leave(conversationId: Int) async throws {}

    func set(_ rows: [Conversation]) {
        cell.update { $0.value = rows }
    }
}

/// Avatar bytes after a short delay, recording how many requests ran at once.
actor CountingAvatars: AvatarRepository {
    private(set) var requests: [String] = []
    private(set) var maxInFlight = 0
    private var inFlight = 0

    func avatar(userId: String) async -> Data? {
        requests.append(userId)
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        try? await Task.sleep(for: .milliseconds(20))
        inFlight -= 1
        return userId.hasPrefix("missing") ? nil : Data(userId.utf8)
    }
}
