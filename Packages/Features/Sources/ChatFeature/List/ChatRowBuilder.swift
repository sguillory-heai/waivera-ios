import Foundation
import WaiveraData

/// Turns one conversation into its inbox row: title, preview, sender prefix, typing line, badges
/// and the spoken label. Plain values in, so the list model only supplies what changes.
struct ChatRowBuilder {
    let text: any ChatListText
    let typingUserIds: [String]
    let timeLabel: String
    /// The badge was cleared optimistically and the server has not caught up yet.
    let isMarkedRead: Bool
    let isOpeningCall: Bool
    let arrivalKey: Int?
    /// A message of mine in this conversation never went out.
    var isSendFailed = false

    func row(_ conversation: Conversation) -> ChatRow {
        let preview = ConversationPresentation.preview(conversation.lastMessage, text: text)
        let title = ConversationPresentation.title(conversation, text: text)
        let sender = ConversationPresentation.senderPrefix(conversation, preview: preview, text: text)
        let typingLabel = ConversationPresentation.typingLabel(
            conversation,
            typingUserIds: typingUserIds,
            text: text
        )
        let isCallLive = conversation.activeCall != nil
        let unread = isMarkedRead ? 0 : conversation.unreadCount
        let spokenPreview = spokenPreview(
            isCallLive: isCallLive,
            typingLabel: typingLabel,
            sender: sender,
            preview: preview.text
        )
        let isChannel = conversation.kind == .channel
        let titleParts = ConversationPresentation.titleParts(conversation, text: text)
        return ChatRow(
            id: conversation.id,
            title: title,
            titleName: titleParts?.name,
            titleCompactCount: titleParts?.compact,
            leading: ConversationPresentation.leading(conversation),
            preview: preview.text,
            previewKind: preview.kind,
            senderPrefix: sender,
            typingLabel: typingLabel,
            typingNamesEnd: typingLabel == nil
                ? nil
                : ConversationPresentation.typingNamesEnd(conversation, typingUserIds: typingUserIds, text: text),
            timeLabel: timeLabel,
            unreadCount: unread,
            hasAttachment: conversation.lastMessage.map { $0.attachment != nil && !$0.isDeleted } ?? false,
            isChannel: isChannel,
            isReadOnly: isChannel && !conversation.canWrite,
            isCallLive: isCallLive,
            isOpeningCall: isOpeningCall,
            arrivalKey: arrivalKey,
            isSendFailed: isSendFailed,
            accessibilityText: ConversationPresentation.accessibilityText(
                title: title,
                previewLine: spokenPreview,
                timeLabel: timeLabel,
                unreadCount: unread,
                text: text
            )
        )
    }

    /// What VoiceOver reads for the preview line: a live call, a failed send or typing wins over
    /// the last message.
    private func spokenPreview(isCallLive: Bool, typingLabel: String?, sender: String?, preview: String) -> String {
        if isCallLive { return text.callInProgress }
        if isSendFailed { return text.notSent }
        if let typingLabel { return typingLabel }
        if let sender { return text.senderPreview(sender: sender, preview: preview) }
        return preview
    }
}
