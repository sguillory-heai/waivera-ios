import Foundation
import WaiveraAPI
import WaiveraRealtime

/// The one normalizer for chat DTOs from every endpoint and the hub (02 §3: "one DTO + one
/// normalizer"). `viewerId` is the backend user id of the signed-in user.
public struct ChatMapper: Sendable {
    public var viewerId: String

    public init(viewerId: String) {
        self.viewerId = viewerId
    }

    // MARK: Messages

    /// `nil` when the payload has no usable conversation id (05 §4).
    public func message(_ dto: MessageSendResponse, conversationId fallback: Int? = nil) -> ChatMessage? {
        guard let conversationId = dto.conversationId.flatMap({ $0 > 0 ? $0 : nil }) ?? fallback, conversationId > 0
        else { return nil }
        let authorId = dto.authorId
        var message = ChatMessage(
            id: dto.id,
            conversationId: conversationId,
            isMine: authorId == viewerId,
            createdAt: dto.createDate
        )
        message.clientMessageId = dto.clientMessageId?.lowercased()
        message.author = dto.author.flatMap(Self.user)
        message.authorId = authorId
        message.kind = Self.kind(dto.messageType)
        message.isDeleted = dto.isDeleted ?? false
        message.isEdited = dto.isEdited ?? false
        message.editedAt = dto.updateDate
        message.parentMessageId = dto.parentMessageId.flatMap { $0 > 0 ? $0 : nil }
        message.threadRootMessageId = dto.threadRootMessageId.flatMap { $0 > 0 ? $0 : nil }
        message.threadReplyCount = dto.threadReplyCount ?? 0
        message.isBookmarked = dto.isBookmarked
        message.callRecordId = dto.callRecordId
        message.systemEventType = dto.systemEventType
        message.systemEventData = dto.systemEventData
        message.isBot = dto.isBot == true || dto.botId != nil || (authorId?.hasPrefix("bot:") ?? false)
        message.reactions = (dto.reactions ?? []).compactMap(Self.reaction)
        // Deleted rows keep no content on the device, whatever the endpoint sent (gap G-11).
        guard !message.isDeleted else { return message }
        message.doc = dto.parsedMessageDoc
        message.plaintext = dto.messagePlaintext?.nilIfBlank
        message.content = dto.messageContent?.nilIfBlank
        message.attachment = Self.attachment(dto)
        return message
    }

    static func user(_ dto: UserInfoResponse) -> ChatUser? {
        guard let id = dto.id?.trimmed, !id.isEmpty else { return nil }
        return ChatUser(
            id: id,
            firstName: dto.firstName,
            lastName: dto.lastName,
            displayName: dto.displayName,
            email: dto.email,
            avatarURL: dto.avatarUrl
        )
    }

    static func kind(_ type: MessageType?) -> ChatMessage.Kind {
        switch type {
        case nil, .user: .user
        case .system: .system
        case .channelEvent: .channelEvent
        case .unknown: .unknown
        }
    }

    static func reaction(_ dto: ReactionResponse) -> Reaction? {
        guard let userId = dto.userId, let emoji = dto.reactionType?.trimmed, !emoji.isEmpty else { return nil }
        return Reaction(userId: userId, fullName: dto.fullName?.nilIfBlank, emoji: emoji)
    }

    static func attachment(_ dto: MessageSendResponse) -> Attachment? {
        guard let url = dto.attachmentUrl?.trimmed, !url.isEmpty else { return nil }
        let name = (dto.attachmentOriginalName ?? dto.attachmentName)?.nilIfBlank
        return Attachment(
            url: url,
            kind: Attachment.kind(contentType: dto.attachmentContentType, type: dto.attachmentType, name: name ?? url),
            name: name,
            contentType: dto.attachmentContentType?.nilIfBlank,
            size: dto.attachmentSize,
            scanStatus: dto.attachmentScanStatus.map(scanStatus) ?? .clean
        )
    }

    static func scanStatus(_ raw: String) -> Attachment.ScanStatus {
        Attachment.ScanStatus(rawValue: raw.lowercased()) ?? .unknown
    }

    // MARK: Conversations

    public func conversation(_ dto: ConversationResponse) -> Conversation? {
        guard dto.id > 0 else { return nil }
        let participants = (dto.participants ?? []).compactMap(Self.user)
        var lastMessage = dto.lastMessage.flatMap { message($0, conversationId: dto.id) }
        if var preview = lastMessage, preview.author == nil, let authorId = preview.authorId {
            // `/api/chat/all` has no author object; resolve it from the participants (G-05).
            preview.author = participants.first { $0.id == authorId }
            lastMessage = preview
        }
        let isChannel = dto.isChannel == true || dto.channel != nil
        var conversation = Conversation(
            id: dto.id,
            kind: kind(isChannel: isChannel, dto: dto, participants: participants, lastMessage: lastMessage),
            viewerId: viewerId,
            participants: participants
        )
        conversation.channel = dto.channel.map(Self.channel)
        conversation.lastMessage = lastMessage
        conversation.unreadCount = max(0, dto.unreadCount ?? 0)
        conversation.lastReadAt = dto.lastReadAt
        conversation.isArchived = dto.channel?.isArchived ?? false
        conversation.activeCall = Self.activeCall(dto)
        return conversation
    }

    private func kind(
        isChannel: Bool,
        dto: ConversationResponse,
        participants: [ChatUser],
        lastMessage: ChatMessage?
    ) -> Conversation.Kind {
        if isChannel { return .channel }
        let isBot =
            dto.isBotDirect == true || participants.contains(where: \.isBot) || lastMessage?.isBot == true
            || (participants.count == 1 && participants.first?.id == viewerId)
        if isBot { return .bot }
        return participants.filter { $0.id != viewerId }.count > 1 ? .group : .direct
    }

    static func channel(_ dto: ChannelDto) -> ChannelInfo {
        ChannelInfo(
            channelId: dto.channelId,
            name: dto.name?.nilIfBlank,
            topic: dto.topic?.nilIfBlank,
            type: dto.channelType?.rawValue,
            isArchived: dto.isArchived,
            canWrite: dto.canWrite
        )
    }

    /// `ongoingCall` first, then `activeMeeting` (03 §19); ended calls are never live (G-10).
    static func activeCall(_ dto: ConversationResponse) -> CallRoom? {
        if let call = dto.ongoingCall, let room = call.roomId?.nilIfBlank, call.status?.isLive ?? true {
            return CallRoom(roomId: room, startedAt: call.startTime)
        }
        if let meeting = dto.activeMeeting, let room = meeting.roomId?.nilIfBlank {
            return CallRoom(roomId: room, calendarEventId: meeting.calendarEventId, startedAt: meeting.startDate)
        }
        return nil
    }

    // MARK: Activity

    public func activity(_ dto: ChatActivityResponse) -> ActivityItem? {
        guard dto.conversationId > 0, dto.messageId > 0 else { return nil }
        let kind: ActivityItem.Kind =
            switch dto.activityType {
            case .mention: .mention
            case .threadReply: .threadReply
            case .reaction: .reaction
            case .unknown, nil: .unknown
            }
        var item = ActivityItem(
            id: dto.id,
            kind: kind,
            conversationId: dto.conversationId,
            messageId: dto.messageId,
            isRead: dto.read ?? false
        )
        item.actorUserId = dto.actorUserId?.nilIfBlank
        item.actorDisplayName = dto.actorDisplayName?.nilIfBlank
        item.threadRootMessageId = dto.threadRootMessageId.flatMap { $0 > 0 ? $0 : nil }
        item.reactionType = dto.reactionType?.nilIfBlank
        item.summary = dto.summary?.nilIfBlank
        item.createdAt = dto.createdAt
        return item
    }

    // MARK: Hub events

    /// A `ReceiveMessageUpdate` applied to a cached message. The edit replaces the body
    /// wholesale: a plain-text edit drops the old rich-text doc.
    public static func applying(_ update: MessageUpdateEvent, to message: ChatMessage) -> ChatMessage {
        var updated = message
        updated.isEdited = update.isEdited ?? true
        updated.editedAt = update.updateDate ?? message.editedAt
        var probe = MessageSendResponse(id: message.id, conversationId: message.conversationId)
        probe.messageDoc = update.messageDoc
        updated.doc = probe.parsedMessageDoc
        updated.content = update.newContent?.nilIfBlank
        updated.plaintext = update.messagePlaintext?.nilIfBlank ?? (updated.doc == nil ? updated.content : nil)
        return updated
    }

    public static func applying(_ delete: MessageDeleteEvent, to message: ChatMessage) -> ChatMessage {
        var deleted = message
        deleted.isDeleted = true
        deleted.doc = nil
        deleted.plaintext = nil
        deleted.content = nil
        deleted.attachment = nil
        return deleted
    }

    /// `ReceiveReaction`: one reaction per user per message (03 §13).
    public static func applying(_ event: ReactionEvent, to message: ChatMessage) -> ChatMessage {
        var updated = message
        let existing = message.reactions.first { $0.userId == event.userId }
        updated.reactions.removeAll { $0.userId == event.userId }
        if event.action != .removed, let emoji = event.reactionType?.trimmed, !emoji.isEmpty {
            updated.reactions.append(Reaction(userId: event.userId, fullName: existing?.fullName, emoji: emoji))
        }
        return updated
    }
}

extension String {
    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : self
    }
}
