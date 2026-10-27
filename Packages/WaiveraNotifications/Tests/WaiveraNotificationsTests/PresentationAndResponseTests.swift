import Testing
import WaiveraRouting

@testable import WaiveraNotifications

struct ForegroundPresentationTests {
    private let chat42 = PushPayload.chat(ChatPush(conversationID: 42, messageID: 1))

    private func context(live: Bool, banners: Bool = true, sound: Bool = true) -> ForegroundContext {
        ForegroundContext(isConversationLive: live, inAppBannersEnabled: banners, soundEnabled: sound)
    }

    @Test func chatPushIsHiddenWhenTheDataLayerSaysItsConversationIsLive() {
        #expect(ForegroundPresentationPolicy.decide(for: chat42, context: context(live: true)) == .suppressed)
    }

    @Test func chatPushIsShownWhenTheConversationIsNotLive() {
        let decision = ForegroundPresentationPolicy.decide(for: chat42, context: context(live: false))
        #expect(decision == PresentationDecision(showBanner: true, showInList: true, playSound: true))
    }

    @Test func inAppBannersOffKeepsItInTheListOnly() {
        let decision = ForegroundPresentationPolicy.decide(
            for: .meeting(eventID: "evt_1"),
            context: context(live: false, banners: false)
        )
        #expect(decision == PresentationDecision(showBanner: false, showInList: true, playSound: false))
    }

    @Test func soundOffIsSilent() {
        let decision = ForegroundPresentationPolicy.decide(for: chat42, context: context(live: false, sound: false))
        #expect(!decision.playSound)
        #expect(decision.showBanner)
    }

    @Test func nonChatPushesAreNeverHidden() {
        let call = ForegroundPresentationPolicy.decide(
            for: .call(conversationID: 42, roomID: "room_1"),
            context: context(live: true)
        )
        #expect(call.showBanner)
        let meeting = ForegroundPresentationPolicy.decide(for: .meeting(eventID: "evt_1"), context: context(live: true))
        #expect(meeting.showBanner)
    }
}

struct NotificationResponseTests {
    private let chat = PushPayload.chat(ChatPush(conversationID: 7, messageID: 9312))

    @Test func tapOpensTheTarget() {
        #expect(
            NotificationResponseInterpreter.interpret(actionIdentifier: NotificationActionID.open, payload: chat)
                == .open(.conversation(7, targetMessageID: 9312))
        )
    }

    @Test func replySendsTrimmedText() {
        let action = NotificationResponseInterpreter.interpret(
            actionIdentifier: NotificationActionID.reply,
            payload: chat,
            userText: "  on my way \n"
        )
        #expect(action == .reply(conversationID: 7, threadRootMessageID: nil, text: "on my way"))
    }

    @Test func emptyReplyDoesNothing() {
        #expect(
            NotificationResponseInterpreter.interpret(
                actionIdentifier: NotificationActionID.reply,
                payload: chat,
                userText: "  "
            ) == .none
        )
    }

    @Test func overlongReplyIsTrimmed() {
        let long = String(repeating: "a", count: NotificationResponseInterpreter.maxReplyLength + 10)
        let action = NotificationResponseInterpreter.interpret(
            actionIdentifier: NotificationActionID.reply,
            payload: chat,
            userText: long
        )
        guard case .reply(_, _, let text) = action else {
            Issue.record("expected reply")
            return
        }
        #expect(text.count == NotificationResponseInterpreter.maxReplyLength)
    }

    @Test func markReadCarriesTheMessage() {
        #expect(
            NotificationResponseInterpreter.interpret(actionIdentifier: NotificationActionID.markRead, payload: chat)
                == .markRead(conversationID: 7, messageID: 9312)
        )
    }

    @Test func dismissDoesNothing() {
        #expect(
            NotificationResponseInterpreter.interpret(actionIdentifier: NotificationActionID.dismiss, payload: chat)
                == .none
        )
    }

    @Test func invalidChatTapDoesNotNavigate() {
        #expect(
            NotificationResponseInterpreter.interpret(
                actionIdentifier: NotificationActionID.open,
                payload: .invalidChat
            ) == .none
        )
    }

    @Test func unknownTypeTapOpensInbox() {
        #expect(
            NotificationResponseInterpreter.interpret(
                actionIdentifier: NotificationActionID.open,
                payload: .unknown(type: "x")
            )
                == .open(.inbox)
        )
    }
}

struct NotificationTapRouterTests {
    @Test func sameResponseTwiceNavigatesOnce() {
        var router = NotificationTapRouter()
        #expect(router.handle(key: "a:open", destination: .conversation(7), isAuthenticated: true) == .conversation(7))
        #expect(router.handle(key: "a:open", destination: .conversation(7), isAuthenticated: true) == nil)
    }

    @Test func tapBeforeSignInIsHeldAndReplayedOnce() {
        var router = NotificationTapRouter()
        #expect(router.handle(key: "a", destination: .conversation(7), isAuthenticated: false) == nil)
        #expect(router.didAuthenticate() == .conversation(7))
        #expect(router.didAuthenticate() == nil)
    }

    @Test func secondTapBeforeSignInReplacesTheFirst() {
        var router = NotificationTapRouter()
        _ = router.handle(key: "a", destination: .conversation(7), isAuthenticated: false)
        _ = router.handle(key: "b", destination: .conversation(42), isAuthenticated: false)
        #expect(router.didAuthenticate() == .conversation(42))
    }

    @Test func abandonedSignInDiscardsTheHeldTap() {
        var router = NotificationTapRouter()
        _ = router.handle(key: "a", destination: .conversation(7), isAuthenticated: false)
        router.discardPending()
        #expect(router.didAuthenticate() == nil)
    }

    @Test func rememberedKeysAreBounded() {
        var router = NotificationTapRouter()
        for index in 0...NotificationTapRouter.capacity {
            _ = router.handle(key: "k\(index)", destination: .inbox, isAuthenticated: true)
        }
        // The oldest key fell out of the window, so it routes again.
        #expect(router.handle(key: "k0", destination: .inbox, isAuthenticated: true) == .inbox)
        #expect(
            router.handle(key: "k\(NotificationTapRouter.capacity)", destination: .inbox, isAuthenticated: true) == nil
        )
    }
}

struct NotificationPermissionTests {
    @Test func primerShowsOnceBeforeTheSystemIsAsked() {
        #expect(NotificationPermissionPolicy.shouldShowPrimer(authorization: .notDetermined, hasSeenPrimer: false))
        #expect(!NotificationPermissionPolicy.shouldShowPrimer(authorization: .notDetermined, hasSeenPrimer: true))
        for status in [NotificationAuthorization.denied, .authorized, .provisional, .ephemeral] {
            #expect(!NotificationPermissionPolicy.shouldShowPrimer(authorization: status, hasSeenPrimer: false))
        }
    }

    @Test func notNowAsksForQuietDelivery() {
        #expect(NotificationPermissionPolicy.request(for: .enable) == .full)
        #expect(NotificationPermissionPolicy.request(for: .notNow) == .provisional)
    }

    @Test func settingsStatus() {
        #expect(NotificationPermissionPolicy.status(for: .notDetermined) == .notAsked)
        #expect(NotificationPermissionPolicy.status(for: .authorized) == .on)
        #expect(NotificationPermissionPolicy.status(for: .provisional) == .deliveredQuietly)
        #expect(NotificationPermissionPolicy.status(for: .denied) == .offInSystemSettings)
    }

    @Test func deniedDevicesAreNeverRegistered() {
        #expect(!NotificationPermissionPolicy.allowsRegistration(.denied))
        #expect(!NotificationPermissionPolicy.allowsRegistration(.notDetermined))
        #expect(NotificationPermissionPolicy.allowsRegistration(.provisional))
    }
}

struct PrimerSeenStoreTests {
    @Test func remembersThePrimerPerSuite() {
        let suite = "waivera.tests.primer.\(UInt64.random(in: 0...UInt64.max))"
        let store = PrimerSeenStore(suiteName: suite)
        #expect(!store.hasSeen)
        store.markSeen()
        #expect(PrimerSeenStore(suiteName: suite).hasSeen)
    }
}

struct NotificationResponseEventTests {
    @Test func eventInterpretsItsAction() {
        let event = NotificationResponseEvent(
            key: "req:reply",
            actionIdentifier: NotificationActionID.reply,
            payload: .chat(ChatPush(conversationID: 7)),
            userText: "ok"
        )
        #expect(event.action == .reply(conversationID: 7, threadRootMessageID: nil, text: "ok"))
    }
}
