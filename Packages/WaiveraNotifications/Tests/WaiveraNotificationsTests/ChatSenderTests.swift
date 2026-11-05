import Foundation
import Testing

@testable import WaiveraNotifications

struct ChatSenderTests {
    private let chat: [AnyHashable: Any] = [
        "type": "chat", "conversationId": "41", "messageId": "9320", "senderId": "Xk29aPq7LmN3",
        "aps": ["alert": ["title": "Dana Cole", "body": "On my way"]],
    ]

    @Test func personMessageNamesItsSender() {
        #expect(
            ChatSender.from(userInfo: chat, title: " Dana Cole ")
                == ChatSender(userID: "Xk29aPq7LmN3", name: "Dana Cole", conversationID: 41)
        )
    }

    @Test func botMessageWithoutSenderKeepsTheAppIcon() {
        var bot = chat
        bot["senderId"] = nil
        #expect(ChatSender.from(userInfo: bot, title: "Waivera Bot") == nil)
    }

    @Test func unsafeIdOrMissingNameIsIgnored() {
        var unsafe = chat
        unsafe["senderId"] = "../admin"
        #expect(ChatSender.from(userInfo: unsafe, title: "Dana Cole") == nil)
        #expect(ChatSender.from(userInfo: chat, title: "  ") == nil)
    }

    @Test func otherPushesHaveNoSender() {
        let inbox: [AnyHashable: Any] = ["type": "notification", "notificationId": "8f2b", "senderId": "Xk29aPq7LmN3"]
        #expect(ChatSender.from(userInfo: inbox, title: "Task approved") == nil)
    }
}
