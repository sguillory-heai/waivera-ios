import Foundation

/// The copy the inbox rules need as plain strings. Search matches the rendered title and
/// preview (02 §5), so rows are built in the model with their final text; this seam keeps the
/// model free of SwiftUI and lets tests pass English copy without a resource bundle.
protocol ChatListText: Sendable {
    var noMessages: String { get }
    var photo: String { get }
    var fileAttachment: String { get }
    var conversationUpdate: String { get }
    var deletedMessage: String { get }
    var channelFallback: String { get }
    var conversationFallback: String { get }
    var botTitle: String { get }
    var unknownPerson: String { get }
    var you: String { get }
    var someone: String { get }
    var severalTyping: String { get }
    var now: String { get }
    var yesterday: String { get }
    var callInProgress: String { get }
    /// In place of the preview when a message of mine here never went out.
    var notSent: String { get }

    func groupTitle(first: String, others: Int) -> String
    /// A group title's count in short ("+4"), for a row too narrow for "& 4 others".
    func compactGroupCount(_ others: Int) -> String
    func typing(name: String) -> String
    func minutesAgo(_ minutes: Int) -> String
    /// "Jordan: running late" as one string, for VoiceOver and search-free display.
    func senderPreview(sender: String, preview: String) -> String
    func unreadCount(_ count: Int) -> String
}

/// `ChatList.strings` / `ChatList.stringsdict` in this module. Kept apart from
/// `Localizable.strings`, which the conversation screens own.
struct LocalizedChatListText: ChatListText {
    var noMessages: String { ChatListStrings.string("chat.list.preview.none") }
    var photo: String { ChatListStrings.string("chat.list.preview.photo") }
    var fileAttachment: String { ChatListStrings.string("chat.list.preview.file") }
    var conversationUpdate: String { ChatListStrings.string("chat.list.preview.update") }
    var deletedMessage: String { ChatListStrings.string("chat.list.preview.deleted") }
    var channelFallback: String { ChatListStrings.string("chat.list.title.channel") }
    var conversationFallback: String { ChatListStrings.string("chat.list.title.conversation") }
    var botTitle: String { ChatListStrings.string("chat.list.title.bot") }
    var unknownPerson: String { ChatListStrings.string("chat.list.unknownPerson") }
    var you: String { ChatListStrings.string("chat.list.sender.you") }
    var someone: String { ChatListStrings.string("chat.list.typing.someone") }
    var severalTyping: String { ChatListStrings.string("chat.list.typing.several") }
    var now: String { ChatListStrings.string("chat.list.time.now") }
    var yesterday: String { ChatListStrings.string("chat.list.time.yesterday") }
    var callInProgress: String { ChatListStrings.string("chat.list.call.join") }
    var notSent: String { ChatListStrings.string("chat.list.notSent") }

    func groupTitle(first: String, others: Int) -> String {
        ChatListStrings.format("chat.list.title.group", first, others)
    }

    func compactGroupCount(_ others: Int) -> String {
        ChatListStrings.format("chat.list.title.countCompact", others)
    }

    func typing(name: String) -> String { ChatListStrings.format("chat.list.typing.one", name) }

    func minutesAgo(_ minutes: Int) -> String { ChatListStrings.format("chat.list.time.minutes", minutes) }

    func senderPreview(sender: String, preview: String) -> String {
        ChatListStrings.format("chat.list.preview.sender", sender, preview)
    }

    func unreadCount(_ count: Int) -> String { ChatListStrings.format("chat.list.unread", count) }
}

/// Lookup for the chat list and new chat copy.
enum ChatListStrings {
    static let table = "ChatList"

    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: table)
    }

    /// Positional format (`%1$@`, `%2$ld`) with plural rules from the stringsdict.
    static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}
