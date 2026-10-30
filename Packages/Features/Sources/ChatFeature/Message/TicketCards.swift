import Foundation
import WaiveraAPI
import WaiveraData

enum TicketPriorityTone: Hashable, Sendable {
    case critical, high, medium, other

    init(priority: String) {
        switch priority {
        case "CRITICAL", "URGENT": self = .critical
        case "HIGH": self = .high
        case "MEDIUM": self = .medium
        default: self = .other
        }
    }
}

/// A ticket date as shown: a UTC calendar date, the raw value when unparsable, or not set.
enum TicketDate: Hashable, Sendable {
    case notSet
    case onDate(ChatDay)
    case raw(String)
}

/// A bot `ticket.update` card (03 §15): the data layer's parsed payload plus display rules.
struct TicketCard: Hashable, Sendable {
    var notification: TicketNotification
    var created: TicketDate
    var due: TicketDate

    var tone: TicketPriorityTone { TicketPriorityTone(priority: notification.priority) }
}

enum TicketCards {
    /// A bot message: flagged as a bot, a `bot:` author, or a message in a bot conversation.
    static func isBot(_ message: ChatMessage, botConversation: Bool) -> Bool {
        botConversation || message.isBot || message.authorId?.hasPrefix("bot:") == true
            || message.author?.isBot == true
    }

    static func card(for message: ChatMessage, botConversation: Bool) -> TicketCard? {
        guard isBot(message, botConversation: botConversation),
            message.systemEventType == TicketNotification.eventType,
            let notification = TicketNotification(payload: message.systemEventData)
        else { return nil }
        return TicketCard(
            notification: notification,
            created: date(preferred: notification.createdDateLabel, iso: notification.createdAt),
            due: date(preferred: notification.dueDateLabel, iso: notification.dueDate)
        )
    }

    /// Prefers the pre-formatted label unless it is "--". `MM/DD/YYYY` and ISO values are read
    /// as UTC dates.
    static func date(preferred: String?, iso: String?) -> TicketDate {
        let label = preferred.flatMap { $0.isEmpty || $0 == "--" ? nil : $0 }
        guard let value = label ?? iso.flatMap({ $0.isEmpty ? nil : $0 }) else { return .notSet }
        let usParts = value.split(separator: "/")
        if usParts.count == 3, value.count == 10, let month = Int(usParts[0]), let day = Int(usParts[1]),
            let year = Int(usParts[2])
        {
            return validDay(year: year, month: month, day: day).map(TicketDate.onDate) ?? .raw(value)
        }
        let isoParts = value.split(separator: "-")
        if value.count == 10, isoParts.count == 3, let year = Int(isoParts[0]), let month = Int(isoParts[1]),
            let day = Int(isoParts[2]), let valid = validDay(year: year, month: month, day: day)
        {
            return .onDate(valid)
        }
        if let instant = WaiveraInstant.parse(value), let utc = TimeZone(identifier: "UTC") {
            return .onDate(ChatTime.day(instant, zone: utc))
        }
        return .raw(value)
    }

    private static func validDay(year: Int, month: Int, day: Int) -> ChatDay? {
        guard let utc = TimeZone(identifier: "UTC") else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        guard (1...12).contains(month), (1...31).contains(day),
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
            calendar.component(.day, from: date) == day
        else { return nil }
        return ChatDay(year: year, month: month, day: day)
    }
}

/// How a ticket meta row ("Created by", "Due") fits (wave 28 B3): the label keeps its one-line
/// width, and the value either fits whole beside it or wraps in the room it leaves, as long as
/// that room is at least half the row. Otherwise, or above large text, the row stacks.
enum TicketMetaFit {
    static let valueMinFraction: CGFloat = 0.5

    /// The widest the value may be beside its label, or `nil` when the row should stack.
    static func valueMaxWidth(pairWidth: CGFloat, gap: CGFloat, labelWidth: CGFloat, valueWidth: CGFloat) -> CGFloat? {
        let room = pairWidth - gap - labelWidth
        let fits = valueWidth <= room
        return fits || room >= pairWidth * valueMinFraction ? room : nil
    }
}
