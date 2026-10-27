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
        let spokenPreview: String
        if isCallLive {
            spokenPreview = text.callInProgress
        } else if let typingLabel {
            spokenPreview = typingLabel
        } else if let sender {
            spokenPreview = text.senderPreview(sender: sender, preview: preview.text)
        } else {
            spokenPreview = preview.text
        }
        let isChannel = conversation.kind == .channel
        return ChatRow(
            id: conversation.id,
            title: title,
            leading: ConversationPresentation.leading(conversation),
            preview: preview.text,
            previewKind: preview.kind,
            senderPrefix: sender,
            typingLabel: typingLabel,
            timeLabel: timeLabel,
            unreadCount: unread,
            hasAttachment: conversation.lastMessage.map { $0.attachment != nil && !$0.isDeleted } ?? false,
            isChannel: isChannel,
            isReadOnly: isChannel && !conversation.canWrite,
            isCallLive: isCallLive,
            isOpeningCall: isOpeningCall,
            arrivalKey: arrivalKey,
            accessibilityText: ConversationPresentation.accessibilityText(
                title: title,
                previewLine: spokenPreview,
                timeLabel: timeLabel,
                unreadCount: unread,
                text: text
            )
        )
    }
}
