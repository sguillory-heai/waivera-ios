import Testing
import WaiveraRouting

@testable import WaiveraNotifications

struct PushPayloadTests {
    @Test(arguments: [
        "push-chat-message-ios",
        "push-chat-message-ios-no-preview-no-sound",
        "push-chat-message-android",
        "push-chat-message-android-data",
        "push-chat-message-android-silent-no-preview",
    ])
    func modernChatPushOpensTheMessage(fixture: String) throws {
        let payload = PushPayloadParser.parse(userInfo: try FixtureLoader.userInfo(fixture))
        #expect(payload == .chat(ChatPush(conversationID: 7, messageID: 9312, url: "/chats/7")))
        #expect(payload.destination == .conversation(7, targetMessageID: 9312))
    }

    @Test func attachmentOnlyPushParses() throws {
        let payload = PushPayloadParser.parse(
            userInfo: try FixtureLoader.userInfo("push-chat-message-android-attachment-only")
        )
        #expect(payload == .chat(ChatPush(conversationID: 7, messageID: 9320, url: "/chats/7")))
    }

    @Test func expoPushWithNumericIdsParses() throws {
        let payload = PushPayloadParser.parse(userInfo: try FixtureLoader.userInfo("push-chat-message-expo"))
        #expect(payload == .chat(ChatPush(conversationID: 7, messageID: 9312, url: "/chats/7")))
    }

    @Test func iosFixtureCarriesGroupingAndCategory() throws {
        let aps = PushPayloadParser.apsInfo(userInfo: try FixtureLoader.userInfo("push-chat-message-ios"))
        #expect(aps == PushPayload.APSInfo(category: "CHAT_MESSAGE", threadID: "chat-7"))
        #expect(aps.threadID == NotificationCategories.threadIdentifier(conversationID: 7))
    }

    @Test func legacyMeetingOpensTheEvent() throws {
        let payload = PushPayloadParser.parse(userInfo: try FixtureLoader.userInfo("push-legacy-meeting"))
        #expect(payload == .meeting(eventID: "evt_8f2b19c4"))
        #expect(payload.destination == .calendarEvent("evt_8f2b19c4"))
    }

    @Test func legacyCallOpensItsConversation() throws {
        let payload = PushPayloadParser.parse(userInfo: try FixtureLoader.userInfo("push-legacy-call"))
        #expect(payload == .call(conversationID: 7, roomID: "room_7f3c91"))
        #expect(payload.destination == .conversation(7))
    }

    @Test func legacySurveyOpensToday() throws {
        let payload = PushPayloadParser.parse(userInfo: try FixtureLoader.userInfo("push-legacy-survey"))
        #expect(payload == .survey(instanceID: "svy_inst_9931"))
        #expect(payload.destination == .today)
    }

    @Test func legacyPushesWithEmptyIdsFallBack() {
        #expect(
            PushPayloadParser.parse(data: ["NotificationType": "meeting", "CalenderEventId": ""]).destination
                == .schedule
        )
        #expect(
            PushPayloadParser.parse(data: ["NotificationType": "call", "conversationId": ""]).destination == .inbox
        )
    }

    @Test func threadRootOpensTheThreadOverItsConversation() {
        let payload = PushPayloadParser.parse(data: [
            "type": "chat", "conversationId": "7", "messageId": "9331", "threadRootMessageId": "9330",
        ])
        #expect(payload.destination == .thread(rootMessageID: 9330, conversationID: 7, targetMessageID: 9331))
    }

    @Test(arguments: [
        ["type": "chat"], ["type": "chat", "conversationId": "0"], ["type": "chat", "conversationId": "abc"],
        ["type": "chat", "conversationId": "-7"], ["type": "chat", "conversationId": "7.5"],
    ])
    func invalidChatIdsDoNotNavigate(data: [String: String]) {
        let payload = PushPayloadParser.parse(data: data)
        #expect(payload == .invalidChat)
        #expect(payload.destination == nil)
    }

    @Test func unknownTypesOpenTheInbox() {
        #expect(PushPayloadParser.parse(data: ["type": "reaction"]).destination == .inbox)
        #expect(PushPayloadParser.parse(data: ["NotificationType": "signature"]).destination == .inbox)
        #expect(PushPayloadParser.parse(data: [:]) == .unknown(type: nil))
        #expect(PushPayloadParser.parse(data: [:]).destination == .inbox)
    }

    @Test func typeTakesPrecedenceOverLegacyKey() {
        let payload = PushPayloadParser.parse(data: [
            "type": "chat", "conversationId": "3", "NotificationType": "meeting",
        ])
        #expect(payload == .chat(ChatPush(conversationID: 3)))
    }

    @Test func messageIdIsOptional() {
        #expect(
            PushPayloadParser.parse(data: ["type": "CHAT", "conversationId": " 42 "]).destination == .conversation(42)
        )
    }

    @Test func untrustedLegacyIdsAreRejected() {
        let payload = PushPayloadParser.parse(data: ["NotificationType": "meeting", "CalenderEventId": "../admin"])
        #expect(payload == .meeting(eventID: nil))
    }

    @Test func meaningClassification() throws {
        let chat = PushPayloadParser.parse(userInfo: try FixtureLoader.userInfo("push-chat-message-ios"))
        #expect(NotificationMeaning.classify(chat) == .messages)
        #expect(
            NotificationMeaning.classify(chat, aps: .init(category: "group_activity", threadID: nil)) == .groupActivity
        )
        #expect(NotificationMeaning.classify(.meeting(eventID: nil)) == .scheduleChanges)
        #expect(NotificationMeaning.classify(.unknown(type: "x")) == .digest)
    }

    @Test func categoriesCoverEveryMeaningPlusTheServerCategory() {
        let ids = Set(NotificationCategories.all.map(\.identifier))
        #expect(ids == Set(NotificationMeaning.allCases.map(\.rawValue) + ["CHAT_MESSAGE"]))
        let chat = NotificationCategories.all.first { $0.identifier == "CHAT_MESSAGE" }
        #expect(chat?.actions.map(\.identifier) == [NotificationActionID.reply, NotificationActionID.markRead])
        #expect(NotificationCategories.all.first { $0.meaning == .digest }?.actions.isEmpty == true)
    }
}
