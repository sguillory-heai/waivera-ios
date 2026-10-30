import Foundation
import WaiveraData
import WaiveraDesign

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
    private static func placeholder(
        in template: String,
        at start: String.Index,
        next: inout Int
    ) -> (Int?, String.Index)? {
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
        for specifier in ["@", "ld", "d"] where template[cursor...].hasPrefix(specifier) {
            let end = template.index(cursor, offsetBy: specifier.count)
            let argument = position ?? next
            next = argument + 1
            return (argument, end)
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

    /// The celebration sentence. Your own card speaks to you by first name, as Profile and
    /// Schedule do (Android `CelebrationCopy.self`, UI9-05); a teammate's names them in full.
    static func celebration(_ item: CelebrationItem) -> String {
        if item.isMe { return selfCelebration(item) }
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

    /// "1 thing" / "3 things": picks the `.one` or `.other` key for `count`.
    static func plural(_ key: String, _ count: Int, _ more: String...) -> String {
        fill(text(count == 1 ? "\(key).one" : "\(key).other"), [String(count)] + more)
    }

    // MARK: Hero

    static func greeting(_ greeting: Greeting) -> String {
        let key: String =
            switch greeting.part {
            case .morning: "today.greeting.morning"
            case .afternoon: "today.greeting.afternoon"
            case .evening: "today.greeting.evening"
            }
        guard let name = greeting.firstName else { return text(key) }
        return format("\(key).named", name)
    }

    /// "5 of 9 handled today": what VoiceOver reads for the count-only ring.
    static func ring(_ progress: TodayProgress) -> String {
        format("today.ring.label", String(progress.handled), String(progress.total))
    }

    /// "4 things need you", or "Nothing needs you right now".
    static func needsYouHeadline(open: Int) -> String {
        open > 0 ? plural("today.needsYouCount", open) : text("today.needsYouCount.none")
    }

    /// What is waiting, by kind ("2 messages · 1 invite · 1 ticket"); `nil` when nothing is.
    static func subline(_ kinds: [NeedsYouKind: Int]) -> String? {
        RingSubline.text(kinds) { kind, count in plural(kindKey(kind), count) }
    }

    private static func kindKey(_ kind: NeedsYouKind) -> String {
        switch kind {
        case .notSent: "today.kind.notSent"
        case .message: "today.kind.messages"
        case .mention: "today.kind.mentions"
        case .invitation: "today.kind.invites"
        case .ticket: "today.kind.tickets"
        }
    }

    /// The reward hero's line under the headline; the name is the greeting's first name.
    static func caughtUp(handled: Int, firstName: String?) -> String {
        guard handled > 0 else { return text("today.caughtUp.message") }
        guard let firstName else { return plural("today.caughtUp.count", handled) }
        return plural("today.caughtUp.named", handled, firstName)
    }

    /// A stat tile: its number, its label and what VoiceOver reads; a dash until it loads.
    static func stat(_ value: Int?, label key: String) -> StatText {
        let label = text(value == 1 ? "\(key).one" : "\(key).other")
        guard let value else { return StatText(text("today.stat.unknown"), label, format("today.stat.loading", label)) }
        return StatText(String(value), label, format("today.stat.label", String(value), label))
    }

    /// The reward hero's "5/5 handled" tile.
    static func handledStat(_ progress: TodayProgress?) -> StatText {
        let label = text("today.stat.handled")
        guard let progress else {
            return StatText(text("today.stat.unknown"), label, format("today.stat.loading", label))
        }
        let fraction = format("today.stat.fraction", String(progress.handled), String(progress.total))
        return StatText(fraction, label, ring(progress))
    }

    // MARK: Your day

    /// "3 events · 2 hr scheduled", or "Your day is wide open."
    static func daySummary(_ day: DayTimeline) -> String {
        guard day.eventCount > 0 else { return text("today.day.open") }
        return joined(plural("today.day.events", day.eventCount), scheduled(day.scheduled))
    }

    static func scheduled(_ interval: TimeInterval) -> String? {
        let minutesTotal = Int(interval / 60)
        let hours = minutesTotal / 60
        let minutes = minutesTotal % 60
        switch (hours > 0, minutes > 0) {
        case (true, true): return format("today.day.hoursMinutes", String(hours), String(minutes))
        case (true, false): return format("today.day.hours", String(hours))
        case (false, true): return format("today.day.minutes", String(minutes))
        case (false, false): return nil
        }
    }

    // MARK: Needs you

    /// How a conversation is named in a Not sent card.
    static func conversationName(_ conversation: Conversation) -> String {
        switch conversation.title {
        case .person(let name?): return name
        case .group(let first?, let others): return format("today.notSent.group", first, String(others))
        case .channel(let name?): return format("today.notSent.channel", name)
        default: return text("today.notSent.fallback")
        }
    }

    /// A mention card's headline: the summary's own lead, else who mentioned the person.
    static func mentionHeadline(lead: String?, actor: String?) -> String {
        if let lead { return lead }
        if let actor { return format("today.mentionedYou", actor) }
        return text("today.mentionedYou.unknown")
    }

    /// Keeps a ticket key ("WAIV-2527") as one word on screen: its hyphens do not break.
    static func nonBreakingHyphens(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "\u{2011}")
    }

    private static func selfCelebration(_ item: CelebrationItem) -> String {
        let first = GreetingRules.firstName(nil, displayName: item.name)
        switch (item.isBirthday, item.anniversaryYears, first) {
        case (true, .some, let name?): return format("today.celebration.self.both", name)
        case (true, .some, nil): return text("today.celebration.self.unnamed.both")
        case (false, let years?, let name?): return format("today.celebration.self.anniversary", name, String(years))
        case (false, let years?, nil): return format("today.celebration.self.unnamed.anniversary", String(years))
        case (_, _, let name?): return format("today.celebration.self.birthday", name)
        case (_, _, nil): return text("today.celebration.self.unnamed.birthday")
        }
    }

    /// The emoji in the celebration card's own tile; the sentence carries none (Android
    /// `celebrationEmoji`). Celebrations are the one place emoji are allowed.
    static func celebrationEmoji(_ item: CelebrationItem) -> String {
        switch (item.isBirthday, item.anniversaryYears) {
        case (true, .some): text("today.celebration.emoji.both")
        case (true, nil): text("today.celebration.emoji.birthday")
        default: text("today.celebration.emoji.anniversary")
        }
    }

    static func celebrationLabel(_ item: CelebrationItem) -> String {
        switch (item.isBirthday, item.anniversaryYears) {
        case (true, .some): text("today.celebration.label.both")
        case (true, nil): text("today.celebration.label.birthday")
        default: text("today.celebration.label.anniversary")
        }
    }
}

/// A stat tile's words: its number, its label and what VoiceOver reads for it.
struct StatText: Hashable, Sendable {
    var value: String
    var label: String
    var spoken: String

    init(_ value: String, _ label: String, _ spoken: String) {
        self.value = value
        self.label = label
        self.spoken = spoken
    }
}
