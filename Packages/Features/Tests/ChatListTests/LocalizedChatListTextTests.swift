import Foundation
import Testing

@testable import ChatFeature

/// The bundled English copy resolves (a missing key would show the key itself).
struct LocalizedChatListTextTests {
    let text = LocalizedChatListText()

    @Test("Plain strings and formats resolve from ChatList.strings")
    func strings() {
        #expect(text.photo == "Photo")
        #expect(text.botTitle == "Waivera")
        #expect(text.typing(name: "Priya") == "Priya is typing…")
        #expect(text.senderPreview(sender: "Jordan", preview: "on my way") == "Jordan: on my way")
        #expect(ChatListStrings.string("chat.new.title") == "New chat")
    }

    #if canImport(Darwin)
        @Test("Plural rules come from ChatList.stringsdict")
        func plurals() {
            #expect(text.groupTitle(first: "Priya", others: 1) == "Priya & 1 other")
            #expect(text.groupTitle(first: "Priya", others: 2) == "Priya & 2 others")
            #expect(text.minutesAgo(5) == "5m")
            #expect(text.unreadCount(1) == "1 unread message")
        }
    #endif
}
