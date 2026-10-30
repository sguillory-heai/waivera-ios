import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ChatFeature

/// 02 §4-5 row rules and the acceptance checks that need no UI.
struct ConversationPresentationTests {
    let text = EnglishText()

    @Test("A channel object without isChannel renders as a channel with its name")
    func channelObjectMakesAChannel() {
        let conversation = Sample.conversation(
            #"{"id": 41, "participants": [\#(Sample.viewerUser)], "#
                + #""channel": {"channelId": "c1", "name": "  north-team "}}"#
        )
        #expect(ConversationPresentation.title(conversation, text: text) == "north-team")
        #expect(ConversationPresentation.leading(conversation) == .channel(archived: false))
    }

    @Test("An archived channel shows the archive tile and a channel without a name says Channel")
    func archivedChannel() {
        let conversation = Sample.conversation(
            #"{"id": 58, "isChannel": true, "channel": {"name": " ", "isArchived": true, "canWrite": true}}"#
        )
        #expect(ConversationPresentation.leading(conversation) == .channel(archived: true))
        #expect(ConversationPresentation.title(conversation, text: text) == "Channel")
        #expect(!conversation.canWrite)
    }

    @Test("A conversation whose only participant is me is the Waivera bot")
    func legacyBotDirect() {
        let conversation = Sample.conversation(#"{"id": 90, "participants": [\#(Sample.viewerUser)]}"#)
        #expect(ConversationPresentation.title(conversation, text: text) == "Waivera")
        #expect(ConversationPresentation.leading(conversation) == .bot)
        #expect(!conversation.canWrite)
    }

    @Test("A group of four including me reads '<compact first> & 2 others'")
    func groupTitle() {
        let conversation = Sample.conversation(
            #"{"id": 63, "participants": [\#(Sample.viewerUser), \#(Sample.priya), \#(Sample.jordan), \#(Sample.sam)]}"#
        )
        #expect(ConversationPresentation.title(conversation, text: text) == "Priya Raman & 2 others")
        #expect(ConversationPresentation.leading(conversation) == .group)
    }

    @Test("A group of three reads '& 1 other'")
    func groupTitleSingular() {
        let conversation = Sample.conversation(
            #"{"id": 64, "participants": [\#(Sample.viewerUser), \#(Sample.priya), \#(Sample.jordan)]}"#
        )
        #expect(ConversationPresentation.title(conversation, text: text) == "Priya Raman & 1 other")
    }

    /// Spec 02 §9 says `operations.team@…` compacts to "operations.tea…", but the Expo code it
    /// cites cuts the local part only when it is longer than 16 characters, and the code is the
    /// behaviour reference (11 §4). Android follows the code too.
    @Test("An email-named participant compacts to its local part, cut to 15 characters when longer than 16")
    func emailCompaction() {
        let ops = #"{"id": "usr_ops", "email": "operations.team@waivera.example"}"#
        let conversation = Sample.conversation(
            #"{"id": 65, "participants": [\#(Sample.viewerUser), \#(ops), \#(Sample.jordan)]}"#
        )
        #expect(ConversationPresentation.title(conversation, text: text) == "operations.team & 1 other")
        let north = #"{"id": "usr_ops", "email": "operations.team.north@waivera.example"}"#
        let longer = Sample.conversation(
            #"{"id": 66, "participants": [\#(Sample.viewerUser), \#(north), \#(Sample.jordan)]}"#
        )
        #expect(ConversationPresentation.title(longer, text: text) == "operations.team… & 1 other")
    }

    @Test("A direct chat is titled with the peer's name and shows their avatar")
    func directTitle() {
        let conversation = Sample.conversation(#"{"id": 7, "participants": [\#(Sample.viewerUser), \#(Sample.priya)]}"#)
        #expect(ConversationPresentation.title(conversation, text: text) == "Priya Raman")
        #expect(
            ConversationPresentation.leading(conversation) == .direct(userId: "usr_priya_raman", name: "Priya Raman")
        )
    }

    @Test("A direct chat with nobody else is titled Conversation")
    func untitled() {
        let conversation = Conversation(id: 3, kind: .direct, viewerId: Sample.viewer)
        #expect(ConversationPresentation.title(conversation, text: text) == "Conversation")
    }

    // MARK: Preview

    @Test("No last message reads 'No messages yet'")
    func noMessage() {
        #expect(ConversationPresentation.preview(nil, text: text) == .init(text: "No messages yet", kind: .placeholder))
    }

    @Test("An image-only last message reads Photo")
    func photoPreview() {
        var message = Sample.message(id: 1, conversationId: 7, text: "")
        message.plaintext = nil
        message.attachment = Attachment(url: "chat/1.png", kind: .image, name: "IMG_1.png")
        #expect(ConversationPresentation.preview(message, text: text) == .init(text: "Photo", kind: .attachment))
    }

    @Test("A named PDF with no text previews as the file name; an unnamed file as File attachment")
    func filePreview() {
        var message = Sample.message(id: 1, conversationId: 7, text: "")
        message.plaintext = nil
        message.attachment = Attachment(url: "chat/r.pdf", kind: .file, name: " roster.pdf ")
        #expect(ConversationPresentation.preview(message, text: text) == .init(text: "roster.pdf", kind: .attachment))
        message.attachment = Attachment(url: "chat/r.bin", kind: .file)
        #expect(ConversationPresentation.preview(message, text: text).text == "File attachment")
    }

    @Test("A system message with no body reads 'Conversation update'")
    func systemPreview() {
        var message = Sample.message(id: 1, conversationId: 7, text: "")
        message.plaintext = nil
        message.kind = .system
        #expect(
            ConversationPresentation.preview(message, text: text) == .init(text: "Conversation update", kind: .system)
        )
    }

    @Test("System text loses its TIMESTAMP token")
    func systemTimestampToken() {
        var message = Sample.message(id: 1, conversationId: 7, text: "Call ended - {[TIMESTAMP- 08/10/2026 02:20:12]}")
        message.kind = .system
        #expect(ConversationPresentation.preview(message, text: text) == .init(text: "Call ended", kind: .system))
    }

    @Test("A body that cannot be extracted previews blank")
    func blankPreview() {
        var message = Sample.message(id: 1, conversationId: 7, text: "")
        message.plaintext = nil
        #expect(ConversationPresentation.preview(message, text: text) == .init(text: "", kind: .blank))
    }

    @Test("A deleted message never previews its old content")
    func deletedPreview() {
        var message = Sample.message(id: 1, conversationId: 7, text: "secret")
        message.isDeleted = true
        #expect(
            ConversationPresentation.preview(message, text: text) == .init(text: "Message deleted", kind: .placeholder)
        )
    }

    @Test("Only the first line shows, with whitespace collapsed")
    func firstLine() {
        let message = Sample.message(id: 1, conversationId: 7, text: "Van 2   is back\r\nsecond line")
        #expect(ConversationPresentation.preview(message, text: text).text == "Van 2 is back")
    }

    @Test("A TipTap document sent as text previews as its plain text")
    func serializedDocument() {
        let doc =
            #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Hi "},"#
            + #"{"type":"mention","attrs":{"id":"u1","label":"Priya"}}]}]}"#
        let message = Sample.message(id: 1, conversationId: 7, text: doc)
        #expect(ConversationPresentation.preview(message, text: text).text == "Hi @Priya")
    }

    @Test("Simple HTML previews without tags")
    func htmlPreview() {
        let message = Sample.message(id: 1, conversationId: 7, text: "<p>Shift <b>swap</b> &amp; cover</p><p>later</p>")
        #expect(ConversationPresentation.preview(message, text: text).text == "Shift swap & cover")
    }

    // MARK: Sender, typing

    @Test("My own last message is prefixed You; a group message by its author's first name")
    func senderPrefix() {
        var group = Sample.conversation(
            #"{"id": 63, "participants": [\#(Sample.viewerUser), \#(Sample.priya), \#(Sample.jordan)]}"#
        )
        group.lastMessage = Sample.message(id: 5, conversationId: 63, authorId: "usr_jordan_lee", text: "on my way")
        let preview = ConversationPresentation.preview(group.lastMessage, text: text)
        #expect(ConversationPresentation.senderPrefix(group, preview: preview, text: text) == "Jordan")
        group.lastMessage = Sample.message(id: 6, conversationId: 63, authorId: Sample.viewer, text: "thanks")
        #expect(ConversationPresentation.senderPrefix(group, preview: preview, text: text) == "You")
    }

    @Test("A direct chat from the other person has no sender prefix")
    func directHasNoPrefix() {
        var direct = Sample.conversation(#"{"id": 7, "participants": [\#(Sample.viewerUser), \#(Sample.priya)]}"#)
        direct.lastMessage = Sample.message(id: 5, conversationId: 7)
        let preview = ConversationPresentation.preview(direct.lastMessage, text: text)
        #expect(ConversationPresentation.senderPrefix(direct, preview: preview, text: text) == nil)
    }

    @Test("One person typing names them; two say several; nobody shows the preview")
    func typingLabels() {
        let group = Sample.conversation(
            #"{"id": 63, "participants": [\#(Sample.viewerUser), \#(Sample.priya), \#(Sample.jordan)]}"#
        )
        #expect(ConversationPresentation.typingLabel(group, typingUserIds: [], text: text) == nil)
        #expect(
            ConversationPresentation.typingLabel(group, typingUserIds: ["usr_priya_raman"], text: text)
                == "Priya Raman is typing…"
        )
        #expect(
            ConversationPresentation.typingLabel(
                group,
                typingUserIds: ["usr_priya_raman", "usr_jordan_lee"],
                text: text
            )
                == "Several people are typing…"
        )
        #expect(
            ConversationPresentation.typingLabel(group, typingUserIds: ["usr_x"], text: text) == "Someone is typing…"
        )
        #expect(ConversationPresentation.typingLabel(group, typingUserIds: [Sample.viewer], text: text) == nil)
    }

    // MARK: Order and filter

    @Test("Newer activity sorts first; rows without a date sink; ties break by id")
    func order() {
        let older = Sample.conversation(
            #"{"id": 1, "lastMessage": {"id": 10, "createDate": "2026-11-01T14:00:00Z", "messagePlaintext": "a"}}"#
        )
        let newer = Sample.conversation(
            #"{"id": 2, "lastMessage": {"id": 11, "createDate": "2026-11-01T14:01:00Z", "messagePlaintext": "b"}}"#
        )
        let undated = Sample.conversation(#"{"id": 3}"#)
        let undatedHigher = Sample.conversation(#"{"id": 4}"#)
        let sorted = [older, undated, newer, undatedHigher].sorted(by: ConversationPresentation.inboxOrder)
        #expect(sorted.map(\.id) == [2, 1, 4, 3])
    }

    @Test("Zone-less timestamps are read as UTC when ordering")
    func zonelessIsUTC() {
        let zoneless = Sample.conversation(
            #"{"id": 1, "lastMessage": {"id": 10, "createDate": "2026-11-01T14:00:00", "messagePlaintext": "a"}}"#
        )
        #expect(zoneless.activityDate == Date(timeIntervalSince1970: 1_793_541_600))
    }

    @Test("Filters and search compose; search matches title or preview, case-insensitive")
    func filterAndSearch() {
        let row = ChatRow(
            id: 1,
            title: "north-team",
            leading: .channel(archived: false),
            preview: "Roster attached",
            previewKind: .text,
            timeLabel: "",
            unreadCount: 2,
            hasAttachment: false,
            isChannel: true,
            isReadOnly: false,
            isCallLive: false,
            isOpeningCall: false,
            accessibilityText: ""
        )
        #expect(ConversationPresentation.matches(row, filter: .channels, query: " ROSTER "))
        #expect(ConversationPresentation.matches(row, filter: .unread, query: "north"))
        #expect(!ConversationPresentation.matches(row, filter: .all, query: "priya"))
        var read = row
        read.unreadCount = 0
        read.isChannel = false
        #expect(!ConversationPresentation.matches(read, filter: .unread, query: ""))
        #expect(!ConversationPresentation.matches(read, filter: .channels, query: ""))
    }

    @Test("Empty-state reason: search first, then the filter")
    func emptyReasons() {
        #expect(ConversationPresentation.emptyReason(filter: .unread, query: "x") == .noMatches)
        #expect(ConversationPresentation.emptyReason(filter: .unread, query: " ") == .allCaughtUp)
        #expect(ConversationPresentation.emptyReason(filter: .channels, query: "") == .noChannels)
        #expect(ConversationPresentation.emptyReason(filter: .all, query: "") == .noConversations)
    }

    @Test("VoiceOver reads title, preview, time and the unread count")
    func accessibilityText() {
        let spoken = ConversationPresentation.accessibilityText(
            title: "Priya Raman",
            previewLine: "can you cover Friday?",
            timeLabel: "5m",
            unreadCount: 2,
            text: text
        )
        #expect(spoken == "Priya Raman, can you cover Friday?, 5m, 2 unread")
    }
}
