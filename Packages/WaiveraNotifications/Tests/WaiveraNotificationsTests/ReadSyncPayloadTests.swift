import Foundation
import Testing
import WaiveraRouting

@testable import WaiveraNotifications

struct ReadSyncPayloadTests {
    @Test func inboxPushOpensTheInbox() {
        let payload = PushPayloadParser.parse(data: ["type": "notification", "notificationId": "8f2b-19c4"])
        #expect(payload == .inbox(notificationID: "8f2b-19c4", url: nil))
        #expect(payload.destination == .notices)
    }

    @Test func chatReadIsSilent() {
        let payload = PushPayloadParser.parse(
            data: [
                "type": "chat.read", "conversationId": "7", "threadRootMessageId": "90",
                "readAt": "2026-11-04T10:00:00Z",
            ]
        )
        #expect(payload == .chatRead(conversationID: 7, threadRootMessageID: 90))
        #expect(payload.destination == nil)
        #expect(PushPayloadParser.parse(data: ["type": "chat.read"]) == .unknown(type: "chat.read"))
    }

    @Test func notificationReadOneOrAll() {
        #expect(
            PushPayloadParser.parse(data: ["type": "notification.read", "notificationId": "abc"])
                == .notificationRead(notificationID: "abc")
        )
        #expect(
            PushPayloadParser.parse(data: ["type": "notification.read", "all": "true"])
                == .notificationRead(notificationID: nil)
        )
    }

    /// Only `all: "true"` means every row; a single read without a usable id is ignored.
    @Test func aReadWithoutAUsableIdIsNotAll() {
        #expect(PushPayloadParser.parse(data: ["type": "notification.read"]) == .unknown(type: "notification.read"))
        #expect(
            PushPayloadParser.parse(data: ["type": "notification.read", "notificationId": "../x"])
                == .unknown(type: "notification.read")
        )
        #expect(
            PushPayloadParser.parse(data: ["type": "notification.read", "notificationId": " ", "all": "false"])
                == .unknown(type: "notification.read")
        )
    }

    /// A conversation read clears that chat's own alerts, never its thread replies (Android
    /// `cancelConversation`); a thread read clears that thread's only; a late read never clears
    /// an alert newer than it.
    @Test func readsClearOnlyTheirOwnAlerts() {
        let readAt = Date(timeIntervalSince1970: 1_000)
        let before = readAt.addingTimeInterval(-60)
        #expect(ReadAlertMatch.clears(alertRoot: nil, alertDate: before, readRoot: nil, readAt: readAt))
        #expect(!ReadAlertMatch.clears(alertRoot: 90, alertDate: before, readRoot: nil, readAt: readAt))
        #expect(ReadAlertMatch.clears(alertRoot: 90, alertDate: before, readRoot: 90, readAt: readAt))
        #expect(!ReadAlertMatch.clears(alertRoot: nil, alertDate: before, readRoot: 90, readAt: readAt))
        #expect(!ReadAlertMatch.clears(alertRoot: 91, alertDate: before, readRoot: 90, readAt: nil))
        #expect(
            !ReadAlertMatch.clears(
                alertRoot: nil,
                alertDate: readAt.addingTimeInterval(1),
                readRoot: nil,
                readAt: readAt
            )
        )
        #expect(
            ReadAlertMatch.clears(alertRoot: nil, alertDate: readAt.addingTimeInterval(1), readRoot: nil, readAt: nil)
        )
    }

    @Test func threadRootIsReadFromStringsOrNumbers() {
        #expect(ReadAlertMatch.threadRoot(["threadRootMessageId": "90"]) == 90)
        #expect(ReadAlertMatch.threadRoot(["threadRootMessageId": 90]) == 90)
        #expect(ReadAlertMatch.threadRoot(["threadRootMessageId": ""]) == nil)
        #expect(ReadAlertMatch.threadRoot([:]) == nil)
    }
}
