import Foundation
import WaiveraAPI
import WaiveraData

/// Copy for the conversation and thread screens. Lives in its own `Conversation` table so the
/// chat list's `Localizable.strings` stays untouched. Foundation only, so tests can check copy.
enum ConversationStrings {
    static let table = "Conversation"

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: table, bundle: .module, comment: "")
    }

    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: text(key), locale: .current, arguments: arguments)
    }

    /// `key.one` or `key.other`. Plain keys instead of a stringsdict: the app ships English only
    /// and Linux Foundation cannot read stringsdict files, which would leave copy untested.
    static func plural(_ key: String, count: Int, _ arguments: any CVarArg...) -> String {
        let variant = count == 1 ? ".one" : ".other"
        return String(format: text(key + variant), locale: .current, arguments: arguments.isEmpty ? [count] : arguments)
    }

    // MARK: Chrome

    static func title(_ title: ConversationTitle?) -> String {
        switch title {
        case nil, .untitled: text("conversation.fallback.title")
        case .channel(let name): nonBlank(name) ?? text("title.channel")
        case .bot: text("title.bot")
        case .person(let name): nonBlank(name) ?? text("title.person.unknown")
        case .group(let first, let others):
            plural("title.group", count: others, nonBlank(first) ?? text("title.person.unknown"), others)
        }
    }

    static func subtitle(_ subtitle: ConnectionSubtitle) -> String {
        switch subtitle {
        case .connecting: text("subtitle.connecting")
        case .reconnecting: text("subtitle.reconnecting")
        case .offline: text("subtitle.offline")
        }
    }

    static func typing(_ label: TypingLabel) -> String {
        let unknown = text("subtitle.typing.unknown")
        switch label {
        case .one(let name): return format("typing.one", name ?? unknown)
        case .two(let first, let second): return format("typing.two", first ?? unknown, second ?? unknown)
        case .many: return text("typing.many")
        }
    }

    // MARK: Time

    static func relative(_ value: RelativeTime, locale: Locale = .current) -> String {
        switch value {
        case .justNow: text("time.just.now")
        case .seconds(let count): plural("time.seconds", count: count)
        case .minutes(let count): plural("time.minutes", count: count)
        case .hours(let count): plural("time.hours", count: count)
        case .days(let count): plural("time.days", count: count)
        case .onDate(let day, let showYear): ChatTime.shortDate(day, showYear: showYear, locale: locale)
        }
    }

    static func day(_ label: DayLabel, locale: Locale = .current) -> String {
        switch label {
        case .today: text("day.today")
        case .onDate(let day): ChatTime.shortDate(day, showYear: true, locale: locale)
        }
    }

    static func replies(_ count: Int) -> String { plural("thread.replies", count: count) }

    static func replyCountHeader(_ count: Int) -> String { plural("thread.reply.count.header", count: count) }

    // MARK: Errors and notices

    static func sendError(_ kind: SendErrorKind, noun: SendNoun) -> String {
        let prefix = noun == .reply ? "reply.error." : "send.error."
        let suffix =
            switch kind {
            case .archived: "archived"
            case .readOnly: "read.only"
            case .offline: "offline"
            case .session: "session"
            case .server: "server"
            }
        return text(prefix + suffix)
    }

    static func readOnly(_ reason: ReadOnlyReason) -> (title: String, reason: String) {
        let stem =
            switch reason {
            case .automated: "read.only.bot"
            case .readOnlyChannel: "read.only.channel"
            case .archivedChannel: "read.only.archived"
            case .readOnlyThread: "read.only.thread"
            }
        return (text(stem + ".title"), text(stem + ".reason"))
    }

    static func toast(_ kind: ChatToast.Kind) -> String {
        switch kind {
        case .bookmarkSaved: return text("bookmark.saved")
        case .bookmarkRemoved: return text("bookmark.removed")
        case .fileSaved(let name): return format("file.saved", name)
        case .failed(let action, let detail):
            let title = failedTitle(action)
            guard let detail else { return title }
            return format("snackbar.with.detail", title, detail.userMessage)
        }
    }

    static func failedTitle(_ action: ChatToast.FailedAction) -> String { text(action.rawValue) }

    // MARK: Rows

    static func reactorName(_ name: ReactorName) -> String {
        switch name {
        case .you: text("you")
        case .name(let value), .userId(let value): value
        case .unknown: text("unknown.author")
        }
    }

    static func reactionLabel(_ summary: ReactionSummary) -> String {
        format(summary.mine ? "reaction.label.mine" : "reaction.label", summary.emoji, summary.count)
    }

    static func callTitle(_ outcome: CallOutcome) -> String {
        switch outcome {
        case .declined: text("call.declined")
        case .missed: text("call.missed")
        case .ended: text("call.ended")
        case .inProgress: text("call.live")
        }
    }

    /// The screen reader sentence for a message row: "You: …" or "Priya: …".
    static func rowLabel(author: String?, isMine: Bool, body: String) -> String {
        isMine ? format("row.mine", body) : format("row.other", author ?? text("unknown.author"), body)
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
