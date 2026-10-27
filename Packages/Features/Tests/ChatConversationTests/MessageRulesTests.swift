import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ChatFeature

@Suite("Chat time")
struct ChatTimeTests {
    private let chicago = Fixture.chicago
    private let now = Fixture.instant("2026-11-01T16:30:00Z")
    private let usLocale = Locale(identifier: "en_US_POSIX")

    private func ago(_ seconds: TimeInterval) -> RelativeTime {
        ChatTime.relative(now.addingTimeInterval(-seconds), now: now, zone: chicago)
    }

    @Test func relativeBuckets() {
        #expect(ago(0) == .justNow)
        #expect(ago(9) == .justNow)
        #expect(ago(45) == .seconds(45))
        #expect(ago(150) == .minutes(2))
        #expect(ago(3 * 3_600 + 59) == .hours(3))
        #expect(ago(6 * 86_400) == .days(6))
    }

    @Test func futureTimestampsReadAsJustNow() {
        #expect(ChatTime.relative(now.addingTimeInterval(30), now: now, zone: chicago) == .justNow)
    }

    @Test func aWeekOrMoreShowsTheDateWithoutTheYearInTheSameYear() {
        #expect(ago(7 * 86_400) == .onDate(ChatDay(year: 2026, month: 10, day: 25), showYear: false))
    }

    @Test func anotherYearShowsTheYear() {
        let old = Fixture.instant("2025-12-31T18:00:00Z")
        #expect(
            ChatTime.relative(old, now: now, zone: chicago)
                == .onDate(ChatDay(year: 2025, month: 12, day: 31), showYear: true)
        )
    }

    @Test func elapsedDaysCountRealTimeAcrossTheFallBackChange() {
        // DST boundary: 2026-10-31 11:30 CDT to 2026-11-01 10:30 CST is exactly 24 hours.
        let dayBefore = Fixture.instant("2026-10-31T16:30:00Z")
        #expect(ChatTime.relative(dayBefore, now: now, zone: chicago) == .days(1))
        #expect(ChatTime.day(dayBefore, zone: chicago) == ChatDay(year: 2026, month: 10, day: 31))
    }

    @Test func clockUsesTheGivenZoneOnBothSidesOfTheChange() {
        // DST boundary: 1:30 AM happens twice in Chicago on 2026-11-01.
        #expect(ChatTime.clock(Fixture.instant("2026-11-01T06:30:00Z"), zone: chicago, locale: usLocale) == "1:30 AM")
        #expect(ChatTime.clock(Fixture.instant("2026-11-01T07:30:00Z"), zone: chicago, locale: usLocale) == "1:30 AM")
    }

    @Test func dayLabelIsTodayOrTheDate() {
        let today = ChatDay(year: 2026, month: 11, day: 1)
        let yesterday = ChatDay(year: 2026, month: 10, day: 31)
        #expect(DayLabel.of(today, today: today) == .today)
        #expect(DayLabel.of(yesterday, today: today) == .onDate(yesterday))
    }

    @Test func shortDateFormats() {
        #expect(
            ChatTime.shortDate(ChatDay(year: 2026, month: 10, day: 20), showYear: false, locale: usLocale) == "Oct 20"
        )
        #expect(
            ChatTime.shortDate(ChatDay(year: 2025, month: 10, day: 20), showYear: true, locale: usLocale)
                == "Oct 20, 2025"
        )
    }

    @Test func theChatClockReadsTheZoneOnEveryUse() throws {
        final class Box: @unchecked Sendable { var zone = Fixture.chicago }
        let box = Box()
        let clock = ChatClock(timeZone: { box.zone })
        #expect(clock.timeZone == Fixture.chicago)
        box.zone = try #require(TimeZone(identifier: "Europe/London"))
        #expect(clock.timeZone.identifier == "Europe/London")
    }
}

@Suite("System messages and call logs")
struct SystemMessageTests {
    private let base = Fixture.base

    @Test func timestampTokenIsRemovedAndReadAsUtc() {
        let parsed = SystemMessages.parse("Priya joined the channel - {[TIMESTAMP- 10/20/2026 14:05:09]}")
        #expect(parsed.text == "Priya joined the channel")
        #expect(parsed.embeddedTimestamp == Fixture.instant("2026-10-20T14:05:09Z"))
    }

    @Test func invalidTokenDatesAreIgnored() {
        #expect(SystemMessages.parse("x {[TIMESTAMP- 13/45/2026 25:00:00]}").embeddedTimestamp == nil)
    }

    @Test func textWithoutATokenIsCollapsedAndTrimmed() {
        #expect(SystemMessages.parse("  a \n b  ") == ParsedSystemMessage(text: "a b", embeddedTimestamp: nil))
        #expect(SystemMessages.parse(nil) == ParsedSystemMessage(text: "", embeddedTimestamp: nil))
    }

    @Test func systemAndChannelEventsAreSystemMessages() {
        var message = Fixture.system(1, "x")
        #expect(SystemMessages.isSystem(message))
        message.kind = .channelEvent
        #expect(SystemMessages.isSystem(message))
        message.kind = .user
        #expect(!SystemMessages.isSystem(message))
    }

    @Test func onlyPositiveCallIdsOnSystemMessagesCount() {
        #expect(SystemMessages.callRecordId(Fixture.system(1, "x")) == 3)
        #expect(SystemMessages.callRecordId(Fixture.system(1, "x", call: 0)) == nil)
        var user = Fixture.system(1, "x")
        user.kind = .user
        #expect(SystemMessages.callRecordId(user) == nil)
    }

    @Test func callOutcomes() {
        func outcome(_ text: String) -> CallOutcome { CallLogs.summarize([Fixture.system(1, text)]).outcome }
        #expect(outcome("Call declined") == .declined)
        #expect(outcome("Call rejected") == .declined)
        #expect(outcome("Missed video call") == .missed)
        #expect(outcome("Video call ended") == .ended)
        #expect(outcome("Video call started") == .inProgress)
        #expect(CallLogs.summarize([Fixture.system(1, "Missed video call")]).isMissed)
    }

    @Test func durationIsTakenVerbatimFromTheEndedText() {
        let messages = [
            Fixture.system(1, "Video call started"),
            Fixture.system(2, "Video call ended in 12m 4s - {[TIMESTAMP- 10/20/2026 15:12:04]}"),
        ]
        #expect(CallLogs.duration(messages) == "12m 4s")
        #expect(CallLogs.summarize(messages).time == Fixture.instant("2026-10-20T15:12:04Z"))
    }

    @Test func durationFallsBackToTheSpanBetweenMessages() {
        func span(_ seconds: TimeInterval) -> String? {
            CallLogs.duration([
                Fixture.system(1, "started"), Fixture.system(2, "joined", at: base.addingTimeInterval(seconds)),
            ])
        }
        #expect(span(45) == "45s")
        #expect(span(724) == "12m 4s")
        #expect(span(180) == "3 min")
        #expect(CallLogs.duration([Fixture.system(1, "started")]) == nil)
    }

    @Test func callTimeFallsBackToTheNewestCreatedAt() {
        let messages = [Fixture.system(1, "started"), Fixture.system(2, "ended", at: base.addingTimeInterval(60))]
        #expect(CallLogs.summarize(messages).time == base.addingTimeInterval(60))
    }
}

@Suite("Ticket cards")
struct TicketCardTests {
    private let payload = #"""
        {"ticketId":"WAIV-2527","title":"Update care plan","url":"https://app.example.test/tickets/WAIV-2527",
        "priority":"high","createdDate":"10/30/2026","dueDateLabel":"--","dueDate":"2026-11-04T23:00:00Z"}
        """#

    private func bot(_ data: JSONValue?) -> ChatMessage {
        var message = Fixture.message(1, author: "bot:3", kind: .system, conversationId: 14)
        message.isBot = true
        message.systemEventType = "ticket.update"
        message.systemEventData = data
        return message
    }

    @Test func aBotTicketUpdateBecomesACard() throws {
        let card = try #require(TicketCards.card(for: bot(Fixture.json(payload)), botConversation: false))
        #expect(card.notification.ticketId == "WAIV-2527")
        #expect(card.notification.type == "Task")
        #expect(card.notification.priority == "HIGH")
        #expect(card.tone == .high)
        #expect(card.notification.createdBy == nil)
        #expect(card.created == .onDate(ChatDay(year: 2026, month: 10, day: 30)))
        // "--" falls back to the ISO value, read as a UTC date.
        #expect(card.due == .onDate(ChatDay(year: 2026, month: 11, day: 4)))
    }

    @Test func stringifiedPayloadsAreUnwrapped() {
        #expect(TicketCards.card(for: bot(.string(payload)), botConversation: false) != nil)
    }

    @Test func aPersonsMessageIsNeverATicket() {
        var human = bot(Fixture.json(payload))
        human.isBot = false
        human.authorId = "usr_priya_raman"
        #expect(TicketCards.card(for: human, botConversation: false) == nil)
        #expect(TicketCards.card(for: human, botConversation: true) != nil)
    }

    @Test func missingRequiredFieldsOrUnsafeUrlsAreDropped() {
        let noTitle = Fixture.json(#"{"ticketId":"1","url":"https://x.test"}"#)
        let unsafe = Fixture.json(#"{"ticketId":"1","title":"t","url":"javascript:alert(1)"}"#)
        #expect(TicketCards.card(for: bot(noTitle), botConversation: true) == nil)
        #expect(TicketCards.card(for: bot(unsafe), botConversation: true) == nil)
    }

    @Test func otherEventTypesAreNotTickets() {
        var message = bot(Fixture.json(payload))
        message.systemEventType = "ticket.created.v2"
        #expect(TicketCards.card(for: message, botConversation: true) == nil)
    }

    @Test func ticketDates() {
        #expect(TicketCards.date(preferred: nil, iso: nil) == .notSet)
        #expect(TicketCards.date(preferred: "--", iso: "") == .notSet)
        #expect(TicketCards.date(preferred: nil, iso: "2026-11-04") == .onDate(ChatDay(year: 2026, month: 11, day: 4)))
        #expect(TicketCards.date(preferred: "next week", iso: nil) == .raw("next week"))
        #expect(TicketCards.date(preferred: "13/45/2026", iso: nil) == .raw("13/45/2026"))
    }

    @Test func botDetection() {
        #expect(TicketCards.isBot(Fixture.message(1, author: "bot:3"), botConversation: false))
        #expect(!TicketCards.isBot(Fixture.message(1, author: "usr_a"), botConversation: false))
    }
}

@Suite("Attachments, errors and permissions")
struct AttachmentAndErrorTests {
    private func attachment(
        _ contentType: String? = nil,
        kind: WaiveraData.Attachment.Kind = .file,
        name: String? = nil
    ) -> WaiveraData.Attachment {
        WaiveraData.Attachment(url: "api/attachments/1", kind: kind, name: name, contentType: contentType)
    }

    @Test func imagesAreRecognisedByContentTypeOrKind() {
        #expect(AttachmentRules.isImage(attachment("image/png")))
        #expect(AttachmentRules.isImage(attachment("jpeg")))
        #expect(AttachmentRules.isImage(attachment(kind: .image)))
        #expect(!AttachmentRules.isImage(attachment("application/pdf")))
    }

    @Test func fileNameFallsBackToTheMessageId() {
        #expect(AttachmentRules.fileName(attachment(name: " Plan.pdf "), messageId: 9) == "Plan.pdf")
        #expect(AttachmentRules.fileName(attachment("application/pdf"), messageId: 9) == "waivera-attachment-9.pdf")
        #expect(AttachmentRules.fileName(attachment(), messageId: -4) == "waivera-attachment-0.bin")
    }

    @Test func mimeTypeIsTakenOrInferred() {
        #expect(AttachmentRules.mimeType(attachment("application/pdf"), messageId: 1) == "application/pdf")
        #expect(AttachmentRules.mimeType(attachment(name: "hours.csv"), messageId: 1) == "text/csv")
        #expect(AttachmentRules.mimeType(attachment(name: "notes"), messageId: 1) == "application/octet-stream")
    }

    @Test func fileKinds() {
        #expect(AttachmentRules.kind(attachment(name: "hours.xlsx"), messageId: 1) == .spreadsheet)
        #expect(AttachmentRules.kind(attachment("application/pdf"), messageId: 1) == .document)
        #expect(AttachmentRules.kind(attachment(name: "clip.mov"), messageId: 1) == .other)
    }

    @Test func savedFileNamesCannotEscapeTheShareFolder() {
        let name = AttachmentRules.sanitizedFileName("../../etc/passwd")
        #expect(!name.contains("/"))
        #expect(
            AttachmentRules.sanitizedFileName(String(repeating: "a", count: 300)).count
                <= AttachmentRules.maxFileNameLength
        )
    }

    @Test func sendErrorsMapFromTypedErrors() {
        #expect(SendErrorKind(.channelArchived) == .archived)
        #expect(SendErrorKind(.channelReadOnly) == .readOnly)
        #expect(SendErrorKind(.forbidden) == .readOnly)
        #expect(SendErrorKind(.offline) == .offline)
        #expect(SendErrorKind(.realtimeUnavailable) == .offline)
        #expect(SendErrorKind(.unauthorized) == .session)
        #expect(SendErrorKind(.server(statusCode: 500)) == .server)
    }

    @Test func actionsFollowWritePermissionAndAuthorship() {
        var mine = Fixture.message(1, author: "usr_me")
        mine.isMine = true
        let writable = ChatActions.model(mine, viewerId: "usr_me", canWrite: true, allowsReply: true)
        #expect(writable.canReact && writable.canReply && writable.canEdit && writable.canDelete && writable.canCopy)
        let readOnly = ChatActions.model(mine, viewerId: "usr_me", canWrite: false, allowsReply: true)
        #expect(
            !readOnly.canReact && !readOnly.canReply && !readOnly.canEdit && !readOnly.canDelete && readOnly.canCopy
        )
        let theirs = ChatActions.model(
            Fixture.message(2, author: "usr_b"),
            viewerId: "usr_me",
            canWrite: true,
            allowsReply: true
        )
        #expect(theirs.canReact && !theirs.canEdit && !theirs.canDelete)
    }

    @Test func deletedAndSystemRowsHaveNoActionSheet() {
        var deleted = Fixture.message(1)
        deleted.isDeleted = true
        #expect(!ChatActions.canOpen(deleted))
        #expect(!ChatActions.canOpen(Fixture.system(2, "joined")))
        #expect(ChatActions.canOpen(Fixture.message(3)))
    }

    @Test func typingLabelsByCount() {
        let names = ["usr_a": "Priya", "usr_b": "Sam"]
        #expect(TypingLabel(userIds: [], names: names) == nil)
        #expect(TypingLabel(userIds: ["usr_a"], names: names) == .one("Priya"))
        #expect(TypingLabel(userIds: ["usr_b", "usr_a"], names: names) == .two("Priya", "Sam"))
        #expect(TypingLabel(userIds: ["usr_a", "usr_b", "usr_c"], names: names) == .many)
    }
}

struct AttachmentFilesTests {
    @Test func sharedCopiesAreRemovedWhenTheSessionEnds() throws {
        let url = try AttachmentFiles.write(Data("roster".utf8), fileName: "roster.pdf")
        #expect(FileManager.default.fileExists(atPath: url.path))
        AttachmentFiles.removeAll()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
