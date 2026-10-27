import Foundation
import WaiveraAPI

/// A bot's ticket update, rendered as a card instead of the message body (03 §15).
/// Defaults the spec gives as copy ("Unknown user", "Not set") are left `nil` so the screen
/// can localize them.
public struct TicketNotification: Sendable, Hashable {
    public static let eventType = "ticket.update"
    static let maxStringLayers = 3

    public var ticketId: String
    public var title: String
    /// Always `http` or `https`; anything else rejects the card.
    public var url: URL
    public var type: String
    /// Upper-cased; `UNSET` when missing.
    public var priority: String
    public var createdBy: String?
    /// Raw values: the screen prefers the label unless it is `--`, and formats dates in UTC.
    public var createdAt: String?
    public var createdDateLabel: String?
    public var dueDate: String?
    public var dueDateLabel: String?

    /// `nil` when the payload lacks an id, a title or a web URL; the message then renders
    /// normally.
    public init?(payload: JSONValue?) {
        guard let object = Self.unwrap(payload)?.objectValue,
            let ticketId = Self.text(object["ticketId"]),
            let title = Self.text(object["title"]),
            let raw = Self.text(object["url"]), let url = URL(string: raw),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        self.ticketId = ticketId
        self.title = title
        self.url = url
        type = Self.text(object["type"]) ?? "Task"
        priority = Self.text(object["priority"])?.uppercased() ?? "UNSET"
        createdBy = Self.text(object["createdBy"])
        createdAt = Self.text(object["createdAt"])
        createdDateLabel = Self.text(object["createdDate"])
        dueDate = Self.text(object["dueDate"])
        dueDateLabel = Self.text(object["dueDateLabel"])
    }

    /// The payload may arrive as JSON encoded in a string, up to three times over.
    static func unwrap(_ value: JSONValue?) -> JSONValue? {
        var current = value
        for _ in 0..<maxStringLayers {
            guard let string = current?.stringValue else { break }
            current = try? WaiveraJSON.decoder().decode(JSONValue.self, from: Data(string.utf8))
        }
        return current
    }

    private static func text(_ value: JSONValue?) -> String? {
        if let number = value?.intValue, value?.stringValue == nil { return String(number) }
        return value?.stringValue?.trimmed.nilIfEmpty
    }
}

extension ChatMessage {
    /// The ticket card for this message, when it is a bot's valid ticket update.
    public var ticket: TicketNotification? {
        guard isBot, systemEventType == TicketNotification.eventType else { return nil }
        return TicketNotification(payload: systemEventData)
    }
}
