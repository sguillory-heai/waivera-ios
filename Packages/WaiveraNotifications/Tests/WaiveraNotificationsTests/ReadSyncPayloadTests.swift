import Testing
import WaiveraRouting

@testable import WaiveraNotifications

struct ReadSyncPayloadTests {
    @Test func inboxPushOpensTheInbox() {
        let payload = PushPayloadParser.parse(data: ["type": "notification", "notificationId": "8f2b-19c4"])
        #expect(payload == .inbox(notificationID: "8f2b-19c4", url: nil))
        #expect(payload.destination == .notices)
        #expect(!payload.isSilentReadSync)
    }

    @Test func chatReadIsSilent() {
        let payload = PushPayloadParser.parse(
            data: [
                "type": "chat.read", "conversationId": "7", "threadRootMessageId": "90",
                "readAt": "2026-11-04T10:00:00Z",
            ]
        )
        #expect(payload == .chatRead(conversationID: 7, threadRootMessageID: 90))
        #expect(payload.isSilentReadSync)
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
}
