import Foundation
import WaiveraData

/// The inbox row rules from 02 §4-5 as pure functions over the data layer's `Conversation`.
/// Kind (channel, bot, group, direct), the semantic title and the merge rules come from the
/// data layer's one normalizer; this turns them into display text.
enum ConversationPresentation {
    struct Preview: Sendable, Hashable {
        var text: String
        var kind: PreviewKind
    }

    // MARK: Title and leading

    static func title(_ conversation: Conversation, text: any ChatListText) -> String {
        switch conversation.title {
        case .channel(let name): name ?? text.channelFallback
        case .bot: text.botTitle
        case .person(let name): name ?? text.unknownPerson
        case .group(let first, let others): text.groupTitle(first: first ?? text.unknownPerson, others: others)
        case .untitled: text.conversationFallback
        }
    }

    /// A group title's cuttable name and its short count ("+2"); `nil` for other titles, which
    /// shrink and then end in "…" as a whole (v7 follow-up, item 4).
    static func titleParts(_ conversation: Conversation, text: any ChatListText) -> (name: String, compact: String?)? {
        guard case .group(let first, let others) = conversation.title else { return nil }
        return (first ?? text.unknownPerson, others > 0 ? text.compactGroupCount(others) : nil)
    }

    static func leading(_ conversation: Conversation) -> RowLeading {
        switch conversation.kind {
        case .channel: .channel(archived: conversation.isArchived || conversation.channel?.isArchived == true)
        case .bot: .bot
        case .group: .group
        case .direct:
            .direct(userId: conversation.peer?.id, name: conversation.peer?.fullName ?? "")
        }
    }

    // MARK: Preview

    /// The preview line (02 §4 "Preview"). Same order as the reference: first line of the body,
    /// then the attachment, then the system placeholder, else blank.
    static func preview(_ message: ChatMessage?, text: any ChatListText) -> Preview {
        guard let message else { return Preview(text: text.noMessages, kind: .placeholder) }
        // A deleted row would otherwise be blank and hydrated again on every refresh.
        if message.isDeleted { return Preview(text: text.deletedMessage, kind: .placeholder) }
        let isSystem = message.kind == .system || message.kind == .channelEvent
        if let body = message.bodyText {
            let plain = PreviewPlainText.plainText(body)
            let line = firstLine(isSystem ? SystemText.clean(plain) : plain)
            if !line.isEmpty { return Preview(text: line, kind: isSystem ? .system : .text) }
        }
        if let attachment = message.attachment {
            if attachment.kind == .image { return Preview(text: text.photo, kind: .attachment) }
            let name = attachment.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Preview(text: name.isEmpty ? text.fileAttachment : name, kind: .attachment)
        }
        if isSystem { return Preview(text: text.conversationUpdate, kind: .system) }
        return Preview(text: "", kind: .blank)
    }

    static func firstLine(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let line =
            normalized.split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        return line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// "You" for my own message; the author's first name in groups and channels; nothing for a
    /// direct chat, bots, placeholders and system rows.
    static func senderPrefix(_ conversation: Conversation, preview: Preview, text: any ChatListText) -> String? {
        guard let message = conversation.lastMessage, preview.kind == .text || preview.kind == .attachment else {
            return nil
        }
        if message.isMine { return text.you }
        guard conversation.kind == .group || conversation.kind == .channel else { return nil }
        let author = conversation.participants.first { $0.id == message.authorId } ?? message.author
        guard let name = author?.fullName, let first = name.split(whereSeparator: { $0.isWhitespace }).first else {
            return nil
        }
        return String(first)
    }

    /// 02 §4 "Typing override". `typingUserIds` already excludes the viewer.
    static func typingLabel(_ conversation: Conversation, typingUserIds: [String], text: any ChatListText) -> String? {
        let ids = Set(typingUserIds).subtracting([conversation.viewerId])
        guard let only = ids.first else { return nil }
        if ids.count > 1 { return text.severalTyping }
        return text.typing(name: typingName(conversation, userId: only, text: text))
    }

    /// Where the one typing person's name ends in `typingLabel` ("Priya Raman" in "Priya Raman is
    /// typing…"), in characters, so a one-line row cuts the name and keeps "is typing…" whole.
    /// `nil` when no name shows (several people) or the copy has none.
    static func typingNamesEnd(_ conversation: Conversation, typingUserIds: [String], text: any ChatListText) -> Int? {
        let ids = Set(typingUserIds).subtracting([conversation.viewerId])
        guard ids.count == 1, let only = ids.first else { return nil }
        let name = typingName(conversation, userId: only, text: text)
        let line = text.typing(name: name)
        guard !name.isEmpty, let range = line.range(of: name, options: .backwards) else { return nil }
        return line.distance(from: line.startIndex, to: range.upperBound)
    }

    private static func typingName(_ conversation: Conversation, userId: String, text: any ChatListText) -> String {
        let name = conversation.participants.first { $0.id == userId }?.fullName
        return (name?.isEmpty == false ? name : nil) ?? text.someone
    }

    // MARK: Order, filter, search

    /// Newest activity first, rows without a date last, ties by id: the data layer's order,
    /// applied again so the screen never depends on how a stream sorted its value.
    static func inboxOrder(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        switch (lhs.activityDate, rhs.activityDate) {
        case (let left?, let right?) where left != right: left > right
        case (.some, nil): true
        case (nil, .some): false
        default: lhs.id > rhs.id
        }
    }

    static func matches(_ row: ChatRow, filter: ChatListFilter, query: String) -> Bool {
        switch filter {
        case .all: break
        case .unread: guard row.isUnread else { return false }
        case .channels: guard row.isChannel else { return false }
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return row.title.lowercased().contains(needle) || row.preview.lowercased().contains(needle)
    }

    static func emptyReason(filter: ChatListFilter, query: String) -> ChatListEmptyReason {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .noMatches }
        switch filter {
        case .unread: return .allCaughtUp
        case .channels: return .noChannels
        case .all: return .noConversations
        }
    }

    // MARK: Accessibility

    /// "Jordan Lee, Jordan: running late, 5m, 2 unread". The unread state is spoken, so it is
    /// never carried by the dot's colour alone (10 §7).
    static func accessibilityText(
        title: String,
        previewLine: String,
        timeLabel: String,
        unreadCount: Int,
        text: any ChatListText
    ) -> String {
        var parts = [title]
        if !previewLine.isEmpty { parts.append(previewLine) }
        if !timeLabel.isEmpty { parts.append(timeLabel) }
        if unreadCount > 0 { parts.append(text.unreadCount(unreadCount)) }
        return parts.joined(separator: ", ")
    }
}
