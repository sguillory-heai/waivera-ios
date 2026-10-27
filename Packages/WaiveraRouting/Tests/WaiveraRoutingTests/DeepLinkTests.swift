import Foundation
import Testing

@testable import WaiveraRouting

struct DeepLinkTests {
    private func parse(_ link: String) -> Destination? {
        URL(string: link).flatMap(DeepLink.destination(from:))
    }

    @Test func tabsRoots() {
        #expect(parse("waivera://today") == .today)
        #expect(parse("waivera://") == .today)
        #expect(parse("waivera://chats") == .inbox)
        #expect(parse("waivera://schedule") == .schedule)
        #expect(parse("waivera://calendar") == .schedule)
        #expect(parse("waivera://activity") == Destination(tab: .today, path: [.activity]))
    }

    @Test func conversationWithAndWithoutTargetMessage() {
        #expect(parse("waivera://chats/7") == .conversation(7))
        #expect(parse("waivera://chats/7?messageId=9312") == .conversation(7, targetMessageID: 9312))
        #expect(parse("waivera://chat/7") == .conversation(7))
    }

    @Test func threadBothForms() {
        let expected = Destination(
            tab: .chat,
            path: [
                .conversation(conversationID: 7, targetMessageID: nil),
                .thread(rootMessageID: 9330, conversationID: 7, targetMessageID: 9331),
            ]
        )
        #expect(parse("waivera://chats/thread/9330?conversationId=7&messageId=9331") == expected)
        #expect(parse("waivera://chats/7/thread/9330?messageId=9331") == expected)
    }

    @Test func threadWithoutConversationOpensThreadAlone() {
        #expect(
            parse("waivera://chats/thread/9330")
                == Destination(
                    tab: .chat,
                    path: [.thread(rootMessageID: 9330, conversationID: nil, targetMessageID: nil)]
                )
        )
    }

    @Test func newChatIsASheet() {
        #expect(parse("waivera://chats/new") == Destination(tab: .chat, sheet: .newChat))
    }

    @Test func calendarEventBothForms() {
        #expect(parse("waivera://calendar/evt_8f2b19c4") == .calendarEvent("evt_8f2b19c4"))
        #expect(parse("waivera://calendar?eventId=evt_8f2b19c4") == .calendarEvent("evt_8f2b19c4"))
    }

    @Test func avatarMenuDestinationsKeepTheCurrentTab() {
        #expect(parse("waivera://profile") == Destination(tab: nil, path: [.profile]))
        #expect(parse("waivera://profile/organization") == Destination(tab: nil, path: [.profile, .organization]))
        #expect(parse("waivera://people") == Destination(tab: nil, path: [.people]))
        #expect(
            parse("waivera://people/usr_priya_raman")
                == Destination(tab: nil, path: [.people, .person(userID: "usr_priya_raman")])
        )
        #expect(parse("waivera://bookmarks") == Destination(tab: nil, path: [.bookmarks]))
        #expect(parse("waivera://settings") == Destination(tab: nil, path: [.settings]))
        #expect(
            parse("waivera://settings/notifications")
                == Destination(tab: nil, path: [.settings, .notificationSettings])
        )
        #expect(
            parse("waivera://settings/appearance") == Destination(tab: nil, path: [.settings, .appearanceSettings])
        )
        #expect(parse("waivera://settings/account") == Destination(tab: nil, path: [.settings, .accountSettings]))
        #expect(
            parse("waivera://settings/account/password")
                == Destination(tab: nil, path: [.settings, .accountSettings, .changePassword])
        )
        #expect(parse("waivera://settings/account/billing") == nil)
        #expect(parse("waivera://settings/notifications/password") == nil)
    }

    @Test func pathOnlyFallbackFromPushURL() {
        #expect(DeepLink.destination(fromPath: "/chats/7") == .conversation(7))
        #expect(DeepLink.destination(fromPath: "/calendar?eventId=evt_8f2b19c4") == .calendarEvent("evt_8f2b19c4"))
        #expect(DeepLink.destination(fromPath: "https://evil.example.com/chats/7") == nil)
        #expect(DeepLink.destination(fromPath: "//evil.example.com/chats/7") == nil)
    }

    @Test(arguments: [
        "https://waivera.example.com/chats/7",
        "waivera://chats/0",
        "waivera://chats/-4",
        "waivera://chats/7.5",
        "waivera://chats/abc",
        "waivera://chats/99999999999999999999999",
        "waivera://chats/7/extra/segments/here",
        "waivera://people/..",
        "waivera://people/usr%2F..%2Fadmin",
        "waivera://people/%3Cscript%3E",
        "waivera://calendar/a/b",
        "waivera://settings/billing",
        "waivera://unknown",
        "waivera://today/extra",
    ])
    func rejectsUntrustedOrUnknownLinks(link: String) {
        #expect(parse(link) == nil)
    }

    @Test func invalidMessageIdIsDroppedNotFatal() {
        #expect(parse("waivera://chats/7?messageId=nope") == .conversation(7))
    }

    @Test func opaqueIdLengthIsBounded() {
        #expect(Identifier.opaque(String(repeating: "a", count: 128)) != nil)
        #expect(Identifier.opaque(String(repeating: "a", count: 129)) == nil)
    }
}
