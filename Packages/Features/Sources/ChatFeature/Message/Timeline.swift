import Foundation
import WaiveraAPI
import WaiveraData

/// A server message row.
struct MessageRow: Hashable, Sendable {
    var key: String
    var message: ChatMessage
    var isMine: Bool
    var isBot: Bool
    var groupedWithPrevious: Bool
    var groupedWithNext: Bool
    var rich: RichDocument?
    var ticket: TicketCard?
    var reactions: [ReactionSummary]
    /// True for a message that arrived while the list was on screen (drives the arrival motion).
    var isLiveArrival: Bool = false
}

/// A send the server has not confirmed: Sending…, Waiting for connection…, or Failed with
/// Retry, Edit and Discard (03 §11, 04 §3).
struct PendingRow: Hashable, Sendable {
    var key: String
    var outgoing: OutgoingMessage
    var groupedWithPrevious: Bool
    var groupedWithNext: Bool
    var isLiveArrival: Bool = false
}

/// A plain system line (not a call): centred, italic, never grouped or long-pressable.
struct SystemRow: Hashable, Sendable {
    var key: String
    var message: ChatMessage
    var text: String
}

/// Every system message of one call record, oldest first, as one card (11 §7).
struct CallLogRow: Hashable, Sendable {
    var key: String
    var callRecordId: Int
    var messages: [ChatMessage]
    var summary: CallLogSummary
}

/// One row of a message list. `id` is stable across updates and unique within a list.
enum TimelineItem: Hashable, Sendable, Identifiable {
    case day(key: String, ChatDay)
    case message(MessageRow)
    case pending(PendingRow)
    case system(SystemRow)
    case callLog(CallLogRow)

    var id: String {
        switch self {
        case .day(let key, _): key
        case .message(let row): row.key
        case .pending(let row): row.key
        case .system(let row): row.key
        case .callLog(let row): row.key
        }
    }

    /// Whether `messageId` is drawn by this row (a call card holds several).
    func contains(messageId: Int) -> Bool {
        switch self {
        case .day, .pending: false
        case .message(let row): row.message.id == messageId
        case .system(let row): row.message.id == messageId
        case .callLog(let row): row.messages.contains { $0.id == messageId }
        }
    }

    /// The server message id this row represents, for read state.
    var newestServerMessageId: Int? {
        switch self {
        case .day, .pending: nil
        case .message(let row): row.message.id
        case .system(let row): row.message.id
        case .callLog(let row): row.messages.last?.id
        }
    }
}

/// What grouping needs to know about a server or pending message.
struct GroupingFacts: Sendable {
    var authorId: String?
    var isDeleted: Bool
    var isSystem: Bool
    /// The thread root for a reply, `nil` for a root message.
    var threadKey: Int?
    var createdAt: Date?

    init(_ message: ChatMessage) {
        authorId = message.authorId
        isDeleted = message.isDeleted
        isSystem = SystemMessages.isSystem(message)
        threadKey = message.isThreadReply ? message.threadRootId : nil
        createdAt = message.createdAt
    }

    init(_ outgoing: OutgoingMessage, viewerId: String?) {
        authorId = viewerId
        isDeleted = false
        isSystem = false
        threadKey = outgoing.parentMessageId
        createdAt = outgoing.createdAt
    }
}

enum MessageGrouping {
    static let window: TimeInterval = 5 * 60

    /// `canVisuallyGroupMessages` (03 §4): same author, same thread, same local day, within 5
    /// minutes, neither deleted nor a system line.
    static func canGroup(_ previous: GroupingFacts?, _ current: GroupingFacts?, zone: TimeZone) -> Bool {
        guard let previous, let current, let author = previous.authorId, current.authorId == author,
            !previous.isDeleted, !current.isDeleted, !previous.isSystem, !current.isSystem,
            previous.threadKey == current.threadKey,
            let first = previous.createdAt, let second = current.createdAt,
            first.timeIntervalSince1970 > 0, second.timeIntervalSince1970 > 0,
            ChatTime.day(first, zone: zone) == ChatTime.day(second, zone: zone)
        else { return false }
        let difference = second.timeIntervalSince(first)
        return difference >= 0 && difference <= window
    }
}

/// A server message or an unconfirmed send, in one ordered list.
enum TimelineEntry: Sendable {
    case server(ChatMessage)
    case pending(OutgoingMessage)

    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    var createdAt: Date? {
        switch self {
        case .server(let message): message.createdAt
        case .pending(let outgoing): outgoing.createdAt
        }
    }

    func facts(viewerId: String?) -> GroupingFacts {
        switch self {
        case .server(let message): GroupingFacts(message)
        case .pending(let outgoing): GroupingFacts(outgoing, viewerId: viewerId)
        }
    }

    /// Deterministic order: server messages by time then id, unsent messages last by time
    /// (03 §3, §5).
    static func isOrderedBefore(_ lhs: TimelineEntry, _ rhs: TimelineEntry) -> Bool {
        if lhs.isPending != rhs.isPending { return !lhs.isPending }
        let left = lhs.createdAt ?? .distantPast
        let right = rhs.createdAt ?? .distantPast
        if left != right { return left < right }
        switch (lhs, rhs) {
        case (.server(let first), .server(let second)): return first.id < second.id
        case (.pending(let first), .pending(let second)): return first.clientMessageId < second.clientMessageId
        default: return false
        }
    }
}

struct TimelineInput {
    var messages: [ChatMessage]
    var pending: [OutgoingMessage] = []
    var viewerId: String?
    var zone: TimeZone
    var botConversation: Bool
    var daySeparators: Bool = true
    var liveArrivals: Set<String> = []
}

enum TimelineBuilder {
    /// Builds rows oldest first. Call log messages collapse into one card placed where the
    /// newest of them sits; a day separator precedes the first row of each local day.
    static func build(
        _ input: TimelineInput,
        richDocument: @escaping (ChatMessage) -> RichDocument? = TipTapParser.document(for:)
    ) -> [TimelineItem] {
        let serverClientIds = Set(input.messages.compactMap(\.nonBlankClientId))
        // While a send lands, its outbox row and server copy can both be present: keep the copy.
        let entries =
            (input.messages.map(TimelineEntry.server)
            + input.pending.filter { !serverClientIds.contains($0.clientMessageId) }.map(TimelineEntry.pending))
            .sorted(by: TimelineEntry.isOrderedBefore)
        var calls: [Int: [ChatMessage]] = [:]
        for case .server(let message) in entries {
            if let callId = SystemMessages.callRecordId(message) { calls[callId, default: []].append(message) }
        }
        let rows = TimelineRows(
            input: input,
            ambiguous: ambiguousClientIds(input.messages),
            calls: calls,
            richDocument: richDocument
        )
        let callPosition = calls.mapValues { $0.last?.id }
        var items: [TimelineItem] = []
        var lastDay: ChatDay?
        for (index, entry) in entries.enumerated() {
            // Call log messages show once, as a card where the newest of them sits.
            if case .server(let message) = entry, let callId = SystemMessages.callRecordId(message) {
                if callPosition[callId] != message.id { continue }
            }
            if input.daySeparators, let createdAt = entry.createdAt {
                let day = ChatTime.day(createdAt, zone: input.zone)
                if day != lastDay {
                    items.append(.day(key: "day-\(day)", day))
                    lastDay = day
                }
            }
            let neighbors = Neighbors(
                previous: index > 0 ? entries[index - 1].facts(viewerId: input.viewerId) : nil,
                current: entry.facts(viewerId: input.viewerId),
                next: index + 1 < entries.count ? entries[index + 1].facts(viewerId: input.viewerId) : nil
            )
            items.append(rows.item(for: entry, neighbors: neighbors))
        }
        // A list id must be unique; this is the last guard if the rules above ever miss.
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }

    /// Keyed by client id when there is one, so an optimistic row keeps its identity (and its
    /// place on screen) when the server copy replaces it. Client ids that several server
    /// messages share (seen in real payloads) fall back to the server id.
    static func key(of message: ChatMessage, ambiguous: Set<String> = []) -> String {
        if let clientId = message.nonBlankClientId, !ambiguous.contains(clientId) { return "client-\(clientId)" }
        return "message-\(message.id)"
    }

    static func pendingKey(_ outgoing: OutgoingMessage) -> String { "client-\(outgoing.clientMessageId)" }

    /// Client ids carried by more than one server message.
    static func ambiguousClientIds(_ messages: [ChatMessage]) -> Set<String> {
        var counts: [String: Int] = [:]
        for clientId in messages.compactMap(\.nonBlankClientId) { counts[clientId, default: 0] += 1 }
        return Set(counts.filter { $0.value > 1 }.keys)
    }
}

extension ChatMessage {
    var nonBlankClientId: String? {
        guard let clientMessageId, !clientMessageId.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return clientMessageId
    }
}

/// The grouping facts of a row and the rows on either side of it.
private struct Neighbors {
    var previous: GroupingFacts?
    var current: GroupingFacts
    var next: GroupingFacts?
}

/// Turns one timeline entry into its row: a pending send, a collapsed call log, a system line
/// or a message.
private struct TimelineRows {
    let input: TimelineInput
    let ambiguous: Set<String>
    let calls: [Int: [ChatMessage]]
    let richDocument: (ChatMessage) -> RichDocument?

    func item(for entry: TimelineEntry, neighbors: Neighbors) -> TimelineItem {
        switch entry {
        case .pending(let outgoing):
            let key = TimelineBuilder.pendingKey(outgoing)
            return .pending(
                PendingRow(
                    key: key,
                    outgoing: outgoing,
                    groupedWithPrevious: groupsWithPrevious(neighbors),
                    groupedWithNext: groupsWithNext(neighbors),
                    isLiveArrival: input.liveArrivals.contains(key)
                )
            )
        case .server(let message):
            return item(for: message, neighbors: neighbors)
        }
    }

    private func item(for message: ChatMessage, neighbors: Neighbors) -> TimelineItem {
        if let callId = SystemMessages.callRecordId(message), let group = calls[callId] {
            return .callLog(
                CallLogRow(
                    key: "call-\(callId)",
                    callRecordId: callId,
                    messages: group,
                    summary: CallLogs.summarize(group)
                )
            )
        }
        let key = TimelineBuilder.key(of: message, ambiguous: ambiguous)
        let ticket = TicketCards.card(for: message, botConversation: input.botConversation)
        if ticket == nil, SystemMessages.isSystem(message) {
            let text = SystemMessages.parse(CallLogs.text(of: message)).text
            return .system(SystemRow(key: key, message: message, text: text))
        }
        return .message(
            MessageRow(
                key: key,
                message: message,
                isMine: message.isMine || (input.viewerId != nil && message.authorId == input.viewerId),
                isBot: TicketCards.isBot(message, botConversation: input.botConversation),
                groupedWithPrevious: groupsWithPrevious(neighbors),
                groupedWithNext: groupsWithNext(neighbors),
                rich: message.isDeleted || ticket != nil ? nil : richDocument(message),
                ticket: ticket,
                reactions: ReactionRules.summarize(message.reactions, viewerId: input.viewerId),
                isLiveArrival: input.liveArrivals.contains(key)
            )
        )
    }

    private func groupsWithPrevious(_ neighbors: Neighbors) -> Bool {
        MessageGrouping.canGroup(neighbors.previous, neighbors.current, zone: input.zone)
    }

    private func groupsWithNext(_ neighbors: Neighbors) -> Bool {
        MessageGrouping.canGroup(neighbors.current, neighbors.next, zone: input.zone)
    }
}
