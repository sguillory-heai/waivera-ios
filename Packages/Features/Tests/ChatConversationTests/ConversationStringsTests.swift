import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ChatFeature

@Suite("Conversation copy")
struct ConversationStringsTests {
    @Test func titlesFollowTheChatListRules() {
        #expect(ConversationStrings.title(nil) == "Conversation")
        #expect(ConversationStrings.title(.channel(name: "  ")) == "Channel")
        #expect(ConversationStrings.title(.bot) == "Waivera")
        #expect(ConversationStrings.title(.group(firstName: "Priya", otherCount: 1)) == "Priya & 1 other")
        #expect(ConversationStrings.title(.group(firstName: "Priya", otherCount: 2)) == "Priya & 2 others")
    }

    @Test func pluralsAndFormatsResolve() {
        #expect(ConversationStrings.replies(1) == "1 reply")
        #expect(ConversationStrings.replies(3) == "3 replies")
        #expect(ConversationStrings.relative(.minutes(1)) == "1 minute ago")
        #expect(ConversationStrings.relative(.hours(5)) == "5 hours ago")
        #expect(ConversationStrings.typing(.two("Priya", nil)) == "Priya and Someone are typing…")
    }

    @Test func sendErrorsUseTheRightNoun() {
        #expect(ConversationStrings.sendError(.offline, noun: .message).contains("the message again"))
        #expect(ConversationStrings.sendError(.offline, noun: .reply).contains("the reply again"))
        #expect(ConversationStrings.readOnly(.readOnlyThread).title == "Replies are read only")
    }

    @Test func failureToastsNeverShowServerText() {
        let text = ConversationStrings.toast(.failed(.delete, detail: .offline))
        #expect(text.hasPrefix("Delete failed. "))
        #expect(text == "Delete failed. " + WaiveraError.offline.userMessage)
    }
}
