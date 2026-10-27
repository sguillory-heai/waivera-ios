import Foundation
import WaiveraData

/// User-facing copy for Today and Activity. Values live in `Localizable.strings`; this file
/// is Foundation-only so the copy rules are unit tested on Linux.
enum TodayStrings {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    /// Fills `%@`, `%ld` and positional `%1$@` / `%2$ld` placeholders in order. Arguments are
    /// passed as text so the same code runs where `String` is not a `CVarArg`.
    static func format(_ key: String, _ arguments: String...) -> String {
        fill(text(key), arguments)
    }

    static func fill(_ template: String, _ arguments: [String]) -> String {
        var result = ""
        var index = template.startIndex
        var next = 0
        while index < template.endIndex {
            let character = template[index]
            guard character == "%", let (argument, end) = placeholder(in: template, at: index, next: &next) else {
                result.append(character)
                index = template.index(after: index)
                continue
            }
            if let argument {
                result += argument < arguments.count ? arguments[argument] : ""
            } else {
                result.append("%")
            }
            index = end
        }
        return result
    }

    /// Reads one placeholder starting at the `%` at `start`. Returns the argument index (nil for
    /// a literal `%%`) and where the placeholder ends.
    private static func placeholder(in template: String, at start: String.Index, next: inout Int)
        -> (Int?, String.Index)?
    {
        var cursor = template.index(after: start)
        guard cursor < template.endIndex else { return nil }
        if template[cursor] == "%" { return (nil, template.index(after: cursor)) }
        var digits = ""
        while cursor < template.endIndex, let digit = template[cursor].wholeNumberValue {
            digits.append(String(digit))
            cursor = template.index(after: cursor)
        }
        var position: Int?
        if !digits.isEmpty {
            guard cursor < template.endIndex, template[cursor] == "$", let number = Int(digits) else { return nil }
            position = number - 1
            cursor = template.index(after: cursor)
        }
        for specifier in ["@", "ld", "d"] {
            if template[cursor...].hasPrefix(specifier) {
                let end = template.index(cursor, offsetBy: specifier.count)
                let argument = position ?? next
                next = argument + 1
                return (argument, end)
            }
        }
        return nil
    }

    /// The sentence a row shows for an activity.
    static func summary(_ summary: ActivitySummary) -> String {
        switch summary {
        case .server(let text):
            return text
        case .reaction(let actor, let emoji):
            let name = actor ?? text("today.activity.someone")
            guard let emoji else { return format("today.activity.reacted", name) }
            return format("today.activity.reactedWith", name, emoji)
        case .fallback:
            return text("today.activity.fallback")
        }
    }

    static func kind(_ kind: ActivityItem.Kind) -> String {
        switch kind {
        case .mention: text("today.kind.mention")
        case .threadReply: text("today.kind.reply")
        case .reaction: text("today.kind.reaction")
        case .unknown: text("today.kind.update")
        }
    }

    static func filter(_ filter: ActivityFilter) -> String {
        switch filter {
        case .all: text("today.filter.all")
        case .mentions: text("today.filter.mentions")
        case .replies: text("today.filter.replies")
        case .reactions: text("today.filter.reactions")
        }
    }

    static func snippet(_ snippet: MessageSnippet) -> String {
        switch snippet {
        case .text(let value): value
        case .photo: text("today.snippet.photo")
        case .file(let name): name ?? text("today.snippet.file")
        case .systemUpdate: text("today.snippet.system")
        case .deleted: text("today.snippet.deleted")
        case .none: text("today.snippet.none")
        }
    }

    static func celebration(_ item: CelebrationItem) -> String {
        let name = item.name ?? text("today.celebration.nameFallback")
        switch (item.isBirthday, item.anniversaryYears) {
        case (true, let years?): return format("today.celebration.both", name, String(years))
        case (false, let years?): return format("today.celebration.anniversary", name, String(years))
        default: return format("today.celebration.birthday", name)
        }
    }

    /// "1 unread message" / "3 unread messages".
    static func unreadMessages(_ count: Int) -> String {
        format(count == 1 ? "today.unreadMessages.one" : "today.unreadMessages.other", String(count))
    }

    static func unreadUpdates(_ count: Int, lowerBound: Bool) -> String {
        if lowerBound { return format("today.unreadUpdates.lowerBound", String(count)) }
        return format(count == 1 ? "today.unreadUpdates.one" : "today.unreadUpdates.other", String(count))
    }

    /// "Show 3 more" under a collapsed Needs you.
    static func showMore(_ count: Int) -> String {
        format("today.needsYou.showMore", String(count))
    }

    /// Two parts joined with a middle dot; the second is dropped when empty.
    static func joined(_ first: String, _ second: String?) -> String {
        guard let second, !second.isEmpty else { return first }
        guard !first.isEmpty else { return second }
        return format("today.separator", first, second)
    }

    /// Parts of a spoken label joined with commas, skipping empty ones.
    static func spoken(_ parts: String?...) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
