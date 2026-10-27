import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures

@testable import WaiveraRealtime

struct HubFixtureTests {
    static let chatFixtures = Fixture.allNames.filter { $0.hasPrefix("hub-") && !$0.hasPrefix("hub-video-") }
    static let videoFixtures = Fixture.allNames.filter { $0.hasPrefix("hub-video-") }

    static func invocation(_ name: String) throws -> HubInvocation {
        try WaiveraJSON.decoder().decode(HubInvocation.self, from: Fixture.data(name))
    }

    @Test func fixturesArePresent() {
        #expect(Self.chatFixtures.count >= 25)
        #expect(!Self.videoFixtures.isEmpty)
    }

    @Test(arguments: chatFixtures)
    func everyChatFixtureDecodes(name: String) throws {
        let invocation = try Self.invocation(name)
        #expect(ChatHubContract.Event.signatures[invocation.target] != nil, "unregistered target \(invocation.target)")
        #expect(HubEventDecoder.decode(invocation) != nil)
    }

    @Test(arguments: videoFixtures)
    func everyVideoFixtureDecodes(name: String) throws {
        #expect(HubEventDecoder.decodeVideo(try Self.invocation(name)) != nil)
    }

    @Test func targetsMatchCaseInsensitively() throws {
        var invocation = try Self.invocation("hub-receive-message")
        invocation.target = "receivemessage"
        guard case .message(let message) = HubEventDecoder.decode(invocation) else {
            Issue.record("expected a message")
            return
        }
        #expect(message.conversationId != nil)
    }

    @Test func removedReactionKeepsNullType() throws {
        let event = HubEventDecoder.decode(try Self.invocation("hub-receive-reaction-removed"))
        #expect(
            event
                == .reaction(
                    ReactionEvent(
                        conversationId: 7,
                        messageId: 9312,
                        userId: "usr_jordan_lee",
                        reactionType: nil,
                        action: .removed
                    )
                )
        )
    }

    @Test func reactionActionIsInferredWhenUnknown() {
        let added = HubInvocation(target: "ReceiveReaction", arguments: [7, 1, "u", "👍", "boosted"])
        let removed = HubInvocation(target: "ReceiveReaction", arguments: [7, 1, "u", .null])
        guard case .reaction(let first) = HubEventDecoder.decode(added),
            case .reaction(let second) = HubEventDecoder.decode(removed)
        else {
            Issue.record("expected reactions")
            return
        }
        #expect(first.action == .updated)
        #expect(second.action == .removed)
    }

    @Test func readReceiptWithNullTimestamp() throws {
        let event = HubEventDecoder.decode(try Self.invocation("hub-receive-read-receipt-null"))
        #expect(event == .readReceipt(ReadReceiptEvent(conversationId: 7, userId: "usr_jordan_lee", lastReadAt: nil)))
    }

    @Test func readReceiptTimestampIsUTC() throws {
        guard case .readReceipt(let receipt) = HubEventDecoder.decode(try Self.invocation("hub-receive-read-receipt"))
        else {
            Issue.record("expected a read receipt")
            return
        }
        #expect(receipt.lastReadAt.map(WaiveraInstant.format) == "2026-10-20T14:40:02.118Z")
    }

    @Test func typingEvent() throws {
        let event = HubEventDecoder.decode(try Self.invocation("hub-receive-typing-status-for-user"))
        #expect(event == .typing(TypingEvent(conversationId: 7, userId: "usr_priya_raman", isTyping: true)))
    }

    @Test func removedActivityAcceptsBareOrWrappedID() throws {
        #expect(HubEventDecoder.decode(try Self.invocation("hub-remove-chat-activity")) == .activityRemoved(id: 4410))
        let wrapped = HubInvocation(target: "RemoveChatActivity", arguments: [.object(["id": 12])])
        #expect(HubEventDecoder.decode(wrapped) == .activityRemoved(id: 12))
    }

    @Test func pascalCaseKeysDecode() {
        let invocation = HubInvocation(
            target: "ConversationCallStateChanged",
            arguments: [.object(["ConversationId": 7, "RoomId": "room_1", "Status": "End"])]
        )
        #expect(
            HubEventDecoder.decode(invocation)
                == .callStateChanged(CallStateChangedEvent(conversationId: 7, roomId: "room_1", status: .end))
        )
    }

    @Test func hubChannelTypeIsAnInteger() throws {
        guard
            case .conversationCreated(let conversation) =
                HubEventDecoder.decode(try Self.invocation("hub-conversation-created-channel"))
        else {
            Issue.record("expected a conversation")
            return
        }
        #expect(conversation.channel?.channelType == .team)
    }

    @Test func malformedEventsAreDropped() {
        #expect(HubEventDecoder.decode(HubInvocation(target: "ReceiveMessage", arguments: ["text"])) == nil)
        #expect(
            HubEventDecoder.decode(HubInvocation(target: "ReceiveTypingStatusForUser", arguments: [0, "u", true]))
                == nil
        )
        #expect(HubEventDecoder.decode(HubInvocation(target: "NewMessage", arguments: [])) == nil)
    }
}
