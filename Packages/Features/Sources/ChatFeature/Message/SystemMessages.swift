import Foundation
import WaiveraData

/// A system line with its `{[TIMESTAMP- MM/DD/YYYY HH:MM:SS]}` token removed and parsed as UTC
/// (11 §6).
struct ParsedSystemMessage: Hashable, Sendable {
    var text: String
    var embeddedTimestamp: Date?
}

enum SystemMessages {
    private static let timestampPattern =
        #"\s*-?\s*\{\[\s*TIMESTAMP\s*[-·:]\s*(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s*\]\}\s*"#

    static func parse(_ value: String?) -> ParsedSystemMessage {
        guard let value, !value.isEmpty else { return ParsedSystemMessage(text: "", embeddedTimestamp: nil) }
        let range = NSRange(value.startIndex..., in: value)
        var text = value
        var instant: Date?
        let expression = try? NSRegularExpression(pattern: timestampPattern, options: [.caseInsensitive])
        if let match = expression?.firstMatch(in: value, range: range) {
            let parts = (1...6).compactMap { index -> Int? in
                guard let groupRange = Range(match.range(at: index), in: value) else { return nil }
                return Int(value[groupRange])
            }
            if parts.count == 6 {
                let components = DateComponents(
                    year: parts[2],
                    month: parts[0],
                    day: parts[1],
                    hour: parts[3],
                    minute: parts[4],
                    second: parts[5]
                )
                instant = utcDate(components)
            }
            if let matched = Range(match.range, in: value) {
                text.replaceSubrange(matched, with: "")
            }
        }
        text = text.replacingOccurrences(of: #"\s*-\s*$"#, with: "", options: .regularExpression)
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return ParsedSystemMessage(text: text, embeddedTimestamp: instant)
    }

    static func isSystem(_ message: ChatMessage) -> Bool {
        message.kind == .system || message.kind == .channelEvent
    }

    /// System messages with a positive call record id collapse into one call card (11 §7).
    static func callRecordId(_ message: ChatMessage) -> Int? {
        guard let id = message.callRecordId, id > 0, isSystem(message) else { return nil }
        return id
    }

    /// Rejects impossible dates (13/45, 25:00) instead of letting the calendar roll them over.
    private static func utcDate(_ components: DateComponents) -> Date? {
        guard let month = components.month, let day = components.day, (1...12).contains(month), (1...31).contains(day),
            (0...23).contains(components.hour ?? -1), (0...59).contains(components.minute ?? -1),
            (0...59).contains(components.second ?? -1)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { return nil }
        calendar.timeZone = utc
        guard let date = calendar.date(from: components),
            calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month
        else { return nil }
        return date
    }
}

enum CallOutcome: Hashable, Sendable {
    case declined, missed, ended, inProgress
}

struct CallLogSummary: Hashable, Sendable {
    var outcome: CallOutcome
    /// Verbatim from the "ended in …" text, else computed ("45s", "12m 4s", "3 min"), else nil.
    var duration: String?
    /// Embedded token of the newest message, else its `createdAt`.
    var time: Date?

    var isMissed: Bool { outcome == .declined || outcome == .missed }
}

enum CallLogs {
    private static let durationPattern = #"(?:in|duration:?) +([^-·]+?)(?:\s+-|\s+·|$)"#

    /// `messages` must be one call record's messages, oldest first.
    static func summarize(_ messages: [ChatMessage]) -> CallLogSummary {
        let contents = messages.map { text(of: $0).lowercased() }
        let outcome: CallOutcome =
            if contents.contains(where: { $0.contains("rejected") || $0.contains("declined") }) {
                .declined
            } else if contents.contains(where: { $0.contains("missed") }) {
                .missed
            } else if contents.contains(where: { $0.contains("ended") }) {
                .ended
            } else {
                .inProgress
            }
        let last = messages.last
        return CallLogSummary(
            outcome: outcome,
            duration: duration(messages),
            time: SystemMessages.parse(last.map(text(of:))).embeddedTimestamp ?? last?.createdAt
        )
    }

    static func duration(_ messages: [ChatMessage]) -> String? {
        if let ended = messages.last(where: { text(of: $0).lowercased().contains("ended") }) {
            let value = text(of: ended)
            let range = NSRange(value.startIndex..., in: value)
            let expression = try? NSRegularExpression(pattern: durationPattern, options: [.caseInsensitive])
            if let match = expression?.firstMatch(in: value, range: range),
                let captured = Range(match.range(at: 1), in: value)
            {
                let trimmed = value[captured].trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        guard messages.count >= 2, let first = messages.first?.createdAt, let last = messages.last?.createdAt else {
            return nil
        }
        let elapsed = last.timeIntervalSince(first)
        guard elapsed >= 0 else { return nil }
        let seconds = Int(elapsed.rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder != 0 ? "\(minutes)m \(remainder)s" : "\(minutes) min"
    }

    /// System rows carry their copy in `content`; some payloads only fill `plaintext`.
    static func text(of message: ChatMessage) -> String {
        message.content ?? message.plaintext ?? ""
    }
}
