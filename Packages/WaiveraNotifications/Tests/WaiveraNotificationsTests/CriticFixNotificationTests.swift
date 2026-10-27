import Foundation
import Testing
import WaiveraRouting

@testable import WaiveraNotifications

/// IF-02 (presentation per surface) and IS-07 (responses bound to the account).
@Suite("Critic fixes: notifications")
struct CriticFixNotificationTests {
    private let reply = PushPayload.chat(ChatPush(conversationID: 42, messageID: 9331, threadRootMessageID: 9330))
    private let root = PushPayload.chat(ChatPush(conversationID: 42, messageID: 9332))

    private func context(conversation: Bool, thread: Bool) -> ForegroundContext {
        ForegroundContext(
            isConversationLive: conversation,
            inAppBannersEnabled: true,
            soundEnabled: true,
            isSignedIn: true,
            isThreadLive: thread
        )
    }

    @Test("IF-02: a reply is hidden only while its own thread is on screen")
    func replyFollowsItsThread() {
        #expect(ForegroundPresentationPolicy.decide(for: reply, context: context(conversation: false, thread: true)) == .suppressed)
        #expect(ForegroundPresentationPolicy.decide(for: reply, context: context(conversation: true, thread: false)) != .suppressed)
    }

    @Test("IF-02: a root message shows while only a thread of its conversation is on screen")
    func rootIgnoresTheThread() {
        #expect(ForegroundPresentationPolicy.decide(for: root, context: context(conversation: false, thread: true)) != .suppressed)
        #expect(ForegroundPresentationPolicy.decide(for: root, context: context(conversation: true, thread: false)) == .suppressed)
    }

    private let since = Date(timeIntervalSince1970: 1_792_500_000)

    @Test("IS-07: a notification delivered before this account signed in belongs to someone else")
    func accountPolicy() {
        #expect(!NotificationAccountPolicy.belongsToCurrentAccount(deliveredAt: since.addingTimeInterval(-600), accountSince: since))
        #expect(NotificationAccountPolicy.belongsToCurrentAccount(deliveredAt: since.addingTimeInterval(60), accountSince: since))
        #expect(NotificationAccountPolicy.belongsToCurrentAccount(deliveredAt: since.addingTimeInterval(-1), accountSince: since))
        #expect(NotificationAccountPolicy.belongsToCurrentAccount(deliveredAt: nil, accountSince: since))
        let event = NotificationResponseEvent(
            key: "a:reply",
            actionIdentifier: NotificationActionID.reply,
            payload: reply,
            userText: "On my way",
            deliveredAt: since.addingTimeInterval(-600)
        )
        #expect(!event.belongsToAccount(since: since))
    }

    @Test("IS-07: a tap held while signed out does not open for a later account")
    func heldTapIsBoundToItsAccount() {
        var router = NotificationTapRouter()
        let destination = Destination.conversation(42)
        #expect(
            router.handle(
                key: "a:open",
                destination: destination,
                isAuthenticated: false,
                deliveredAt: since.addingTimeInterval(-600)
            ) == nil
        )
        #expect(router.didAuthenticate(accountSince: since) == nil)
        #expect(router.pending == nil)

        #expect(router.handle(key: "b:open", destination: destination, isAuthenticated: false, deliveredAt: since) == nil)
        #expect(router.didAuthenticate(accountSince: since) == destination)
    }

    @Test("IS-07: sign-out drops a held tap")
    func signOutDropsTheHeldTap() {
        var router = NotificationTapRouter()
        _ = router.handle(key: "a:open", destination: .conversation(42), isAuthenticated: false)
        router.discardPending()
        #expect(router.didAuthenticate() == nil)
    }
}
