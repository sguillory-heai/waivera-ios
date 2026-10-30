import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

struct ChatMapperTests {
    let mapper = ChatMapper(viewerId: viewerId)

    func conversations(_ fixture: String) throws -> [Conversation] {
        let rows: [ConversationResponse]
        let envelope = try? decodeFixture(ApiResponse<[ConversationResponse]>.self, fixture)
        if let data = envelope?.data {
            rows = data
        } else {
            rows = try decodeFixture([ConversationResponse].self, fixture)
        }
        return rows.compactMap(mapper.conversation)
    }

    @Test func unifiedListMapsConversationIdAndResolvesAuthors() throws {
        let rows = try conversations("rest-chat-get-all")
        #expect(rows.map(\.id) == [7, 41, 58])
        let direct = try #require(rows.first)
        #expect(direct.kind == .direct)
        #expect(direct.title == .person(name: "Priya Raman"))
        #expect(direct.lastMessage?.isMine == true)
        // `/all` has no author object; it is resolved from the participants (G-05).
        #expect(direct.lastMessage?.author?.firstName == "Alex")
        #expect(direct.preview == .text("can you cover Friday?"))
        #expect(direct.unreadCount == 1)
        #expect(rows[1].kind == .channel)
        #expect(rows[1].title == .channel(name: "north-team"))
    }

    @Test func archivedChannelIsNotWritable() throws {
        let archived = try #require(try conversations("rest-chat-get-all").first { $0.id == 58 })
        #expect(archived.kind == .channel)
        #expect(!archived.canWrite)
    }

    @Test func groupBotAndCallDetection() throws {
        let rows = try conversations("rest-chat-get-my-conversations")
        let group = try #require(rows.first { $0.id == 11 })
        #expect(group.kind == .group)
        #expect(group.title == .group(firstName: "Priya Raman", otherCount: 1))
        #expect(group.activeCall?.roomId == "room_7f3c91")
        let bot = try #require(rows.first { $0.id == 14 })
        #expect(bot.kind == .bot)
        #expect(bot.title == .bot)
        #expect(!bot.canWrite)
    }

    @Test func activeMeetingBecomesACallRoom() throws {
        let row = try #require(try conversations("rest-chat-get-my-conversations-with-meeting").first)
        #expect(
            row.activeCall
                == CallRoom(
                    roomId: "room_7f3c91",
                    calendarEventId: "evt_8f2b19c4",
                    startedAt: WaiveraInstant.parse("2026-10-20T15:00:00.000000")
                )
        )
    }

    @Test func nullLastMessageShowsNoMessages() throws {
        let row = try #require(try conversations("rest-chat-get-my-conversations-null-last-message").first)
        #expect(row.preview == .noMessages)
    }

    @Test func deletedMessagesKeepNoContent() throws {
        let dto = try #require(
            try decodeFixture([MessageSendResponse].self, "rest-chat-get-messages-pagination-deleted").first
        )
        let deleted = try #require(mapper.message(dto))
        #expect(deleted.isDeleted)
        #expect(deleted.bodyText == nil)
        #expect(deleted.plaintext == nil && deleted.content == nil && deleted.attachment == nil)
    }

    @Test(arguments: [
        "rest-chat-get-messages-pagination", "rest-chat-get-messages-pagination-reply",
        "rest-chat-get-messages-pagination-richtext", "rest-chat-get-messages-pagination-system-message",
        "rest-chat-get-messages-pagination-with-attachment", "rest-chat-get-messages-pagination-with-reaction",
        "rest-chat-get-thread",
    ])
    func everyMessagePageMaps(fixture: String) throws {
        let rows = try decodeFixture([MessageSendResponse].self, fixture)
        let mapped = rows.compactMap { mapper.message($0) }
        #expect(mapped.count == rows.count)
        #expect(mapped.allSatisfy { $0.createdAt != nil })
    }

    @Test func attachmentAndReactionFixtures() throws {
        let withFile = try #require(
            try decodeFixture([MessageSendResponse].self, "rest-chat-get-messages-pagination-with-attachment").first
        )
        let attachment = try #require(mapper.message(withFile)?.attachment)
        #expect(!attachment.url.isEmpty)
        let reacted = try #require(
            try decodeFixture([MessageSendResponse].self, "rest-chat-get-messages-pagination-with-reaction").first
        )
        let groups = try #require(mapper.message(reacted)).reactionGroups(viewerId: viewerId)
        #expect(!groups.isEmpty)
    }

    @Test func richTextPreviewUsesTheDocument() throws {
        let dto = try #require(
            try decodeFixture([MessageSendResponse].self, "rest-chat-get-messages-pagination-richtext").first
        )
        let message = try #require(mapper.message(dto))
        #expect(message.doc != nil)
        #expect(message.bodyText?.isEmpty == false)
    }

    @Test func previewRules() {
        var photo = ChatMessage(id: 1, conversationId: 7)
        photo.attachment = Attachment(url: "chat/a.png", kind: .image)
        #expect(ConversationPreview(photo) == .photo)
        var file = ChatMessage(id: 2, conversationId: 7)
        file.attachment = Attachment(url: "chat/a.pdf", kind: .file, name: " roster.pdf ")
        #expect(ConversationPreview(file) == .file(name: "roster.pdf"))
        var system = ChatMessage(id: 3, conversationId: 7)
        system.kind = .system
        #expect(ConversationPreview(system) == .systemUpdate)
        #expect(ConversationPreview(ChatMessage(id: 4, conversationId: 7)) == .blank)
        var multiline = ChatMessage(id: 5, conversationId: 7)
        multiline.content = "first   line\nsecond"
        #expect(ConversationPreview(multiline) == .text("first line"))
    }

    @Test func attachmentKindPrefersContentType() {
        #expect(Attachment.kind(contentType: "image/png", type: "file", name: "x.bin") == .image)
        #expect(Attachment.kind(contentType: nil, type: "pdf", name: "x.pdf") == .file)
        #expect(Attachment.kind(contentType: nil, type: nil, name: "photo.JPG") == .image)
    }

    @Test func compactNames() {
        #expect(ChatUser(id: "1", email: "averyveryverylongname@example.com").compactName == "averyveryverylo…")
        #expect(ChatUser(id: "2", firstName: "Christopher", lastName: "Johnson").compactName == "C. Johnson")
        // "M. Featherstonehaugh" is still too long, so the full name is truncated (02 §4).
        #expect(
            ChatUser(id: "4", firstName: "Maximiliana", lastName: "Featherstonehaugh").compactName
                == "Maximiliana Feath…"
        )
        #expect(ChatUser(id: "3", firstName: "Bartholomew", lastName: "Lee").compactName == "Bartholomew Lee")
    }

    @Test func richTextRoundTrip() throws {
        let outgoing = try #require(RichText.outgoingDocument(for: "  line one\r\n\r\nline *two*  "))
        #expect(outgoing.text == "line one\n\nline *two*")
        #expect(RichText.plainText(outgoing.doc) == "line one\n\nline *two*")
        #expect(RichText.outgoingDocument(for: " \n ") == nil)
    }

    @Test func reactionEventsReplaceTheUsersReaction() {
        var message = ChatMessage(id: 9312, conversationId: 7)
        message.reactions = [Reaction(userId: "usr_jordan_lee", fullName: "Jordan Lee", emoji: "👍")]
        let updated = ChatMapper.applying(
            ReactionEvent(
                conversationId: 7,
                messageId: 9312,
                userId: "usr_jordan_lee",
                reactionType: "🎉",
                action: .updated
            ),
            to: message
        )
        #expect(updated.reactions == [Reaction(userId: "usr_jordan_lee", fullName: "Jordan Lee", emoji: "🎉")])
        let removed = ChatMapper.applying(
            ReactionEvent(
                conversationId: 7,
                messageId: 9312,
                userId: "usr_jordan_lee",
                reactionType: nil,
                action: .removed
            ),
            to: updated
        )
        #expect(removed.reactions.isEmpty)
    }

    @Test func mergingNeverErasesRicherFields() {
        var rich = ChatMessage(id: 1, conversationId: 7, createdAt: Date(timeIntervalSince1970: 10))
        rich.attachment = Attachment(url: "chat/a.png", kind: .image)
        rich.content = "hi"
        let sparse = ChatMessage(id: 1, conversationId: 7)
        let merged = rich.merging(sparse)
        #expect(merged.attachment == rich.attachment)
        #expect(merged.content == "hi")
        #expect(merged.createdAt == rich.createdAt)
    }

    @Test func activityFixtureMaps() throws {
        let rows = try decodeFixture([ChatActivityResponse].self, "rest-chat-recent-activity")
        let items = rows.compactMap(mapper.activity)
        #expect(items.count == rows.count)
        #expect(Set(items.map(\.kind)).isSubset(of: [.mention, .threadReply, .reaction, .unknown]))
    }

    @Test func destinationsUseTheThreadRoot() {
        var nested = ChatMessage(id: 9332, conversationId: 7)
        nested.parentMessageId = 9331
        nested.threadRootMessageId = 9330
        #expect(
            ChatDestination(message: nested) == .thread(rootMessageId: 9330, conversationId: 7, targetMessageId: 9332)
        )
        #expect(
            ChatDestination(message: ChatMessage(id: 5, conversationId: 7)) == .conversation(id: 7, targetMessageId: 5)
        )
    }
}
