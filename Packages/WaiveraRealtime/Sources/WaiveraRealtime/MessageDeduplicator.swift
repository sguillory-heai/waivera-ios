import Foundation
import WaiveraAPI

/// Drops repeat deliveries of the same message within a window (05 §5.4), with a bounded
/// memory (11 §2.16). A repeat is let through only when it is the first delivery carrying a
/// renderable body.
public struct MessageDeduplicator: Sendable {
    public static let window: TimeInterval = 15
    public static let capacity = 500

    private struct Entry: Sendable {
        var seenAt: Date
        var hadBody: Bool
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []

    public init() {}

    /// Returns true when the message should be processed.
    public mutating func shouldProcess(_ message: MessageSendResponse, now: Date) -> Bool {
        guard let conversationId = message.conversationId else { return false }
        let key = "\(conversationId):\(message.id)"
        let hasBody = Self.hasRenderableContent(message)
        let isRecent = entries[key].map { now.timeIntervalSince($0.seenAt) < Self.window } ?? false
        if let previous = entries[key], isRecent, previous.hadBody || !hasBody {
            return false
        }
        if entries[key] == nil { order.append(key) }
        entries[key] = Entry(seenAt: now, hadBody: hasBody || (entries[key]?.hadBody ?? false))
        if order.count > Self.capacity {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
        return true
    }

    public mutating func reset() {
        entries.removeAll()
        order.removeAll()
    }

    static func hasRenderableContent(_ message: MessageSendResponse) -> Bool {
        let text = message.messagePlaintext ?? message.messageContent ?? ""
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || message.attachmentUrl != nil || message.parsedMessageDoc != nil
    }
}
