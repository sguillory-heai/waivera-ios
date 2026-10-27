import Foundation
import SwiftUI
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraNotifications
import WaiveraRouting
import WaiveraTestSupport

@testable import Waivera

struct FixedTokens: PushTokenSource {
    let token: String?

    func tokens() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        if let token {
            continuation.yield(token)
        }
        return stream
    }
}

@MainActor
final class RecordingAuthorizer: NotificationAuthorizing {
    var status: NotificationAuthorization
    private(set) var requests: [AuthorizationRequest] = []

    init(status: NotificationAuthorization) {
        self.status = status
    }

    func currentAuthorization() async -> NotificationAuthorization { status }

    func request(_ request: AuthorizationRequest) async -> NotificationAuthorization {
        requests.append(request)
        status = request == .full ? .authorized : .provisional
        return status
    }
}

/// `AppModel` over the fake data environment from WaiveraTestSupport, the same one the
/// `-WaiveraFakeServer` launch argument uses.
@MainActor
struct AppModelHarness {
    let fakes: FakeDataEnvironment
    let authorizer: RecordingAuthorizer
    let model: AppModel

    init(
        scenario: FakeDataEnvironment.Scenario = .demo,
        authorization: NotificationAuthorization = .authorized,
        token: String? = "fcm-token",
        route: String? = nil,
        primerSeen: Bool = true,
        configured: Bool = true
    ) {
        fakes = FakeDataEnvironment.make(scenario)
        authorizer = RecordingAuthorizer(status: authorization)
        let primerStore = PrimerSeenStore(suiteName: "waivera.tests.\(UUID().uuidString)")
        if primerSeen {
            primerStore.markSeen()
        }
        var launch = LaunchOptions()
        launch.route = route.flatMap(RouteCatalog.entry(named:))
        model = AppModel(
            environment: AppEnvironment(
                data: configured ? fakes.environment : nil,
                tokenSource: FixedTokens(token: token),
                authorizer: authorizer,
                primerStore: primerStore
            ),
            launch: launch
        )
    }

    var registeredTokens: [String] { fakes.push.registrations.get().map(\.token) }

    /// Lets the model's observation tasks and the registration actor catch up. Only for checking
    /// that something did not happen; wait for things that should happen with `until`.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(80))
    }

    /// Polls `condition` until it holds (true) or two seconds pass (false).
    func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Starts the model and waits for the demo session to reach the tabs (or the primer).
    func startSignedIn() async {
        model.start()
        _ = await until { model.session.isSignedIn && model.authorization != nil }
        await settle()
    }

    func signIn() async throws {
        try await fakes.session.signIn(email: "alex@example.com", password: FakeSessionRepository.password)
        _ = await until { model.session.isSignedIn }
        await settle()
    }
}

private func link(_ text: String) throws -> URL {
    try #require(URL(string: text))
}

@MainActor
struct AppModelGateTests {
    @Test func gateFollowsTheSession() async throws {
        let harness = AppModelHarness(scenario: .signedOut)
        #expect(harness.model.gate == .signIn)
        harness.model.start()
        await harness.settle()
        #expect(harness.model.gate == .signIn)
        try await harness.signIn()
        #expect(harness.model.gate == nil)
        #expect(harness.model.userDisplayName == harness.fakes.data.user.displayName)
    }

    @Test func coldStartShowsLoadingThenTheTabs() async {
        let harness = AppModelHarness()
        #expect(harness.model.gate == .loading)
        harness.model.start()
        #expect(await harness.until { harness.model.gate == nil })
        #expect(harness.fakes.session.calls.count("start") == 1)
    }

    @Test func passwordChangeGate() async {
        let harness = AppModelHarness(scenario: .passwordChange)
        harness.model.start()
        #expect(await harness.until { harness.model.gate == .passwordChange })
    }

    @Test func bootstrapFailureShowsRetryWithClientCopy() async {
        let harness = AppModelHarness(scenario: .signedOut)
        harness.fakes.session.bootstrapFailure.update { $0 = .offline }
        harness.model.start()
        await harness.settle()
        try? await harness.fakes.session.signIn(email: "alex@example.com", password: FakeSessionRepository.password)
        #expect(await harness.until { harness.model.gate == .bootstrapFailed })
        #expect(harness.model.bootstrapFailureMessage == WaiveraError.offline.userMessage)
        harness.fakes.session.bootstrapFailure.update { $0 = nil }
        harness.model.retryBootstrap()
        #expect(await harness.until { harness.model.gate == nil })
    }

    @Test func missingConfigurationShowsItsGateAndRegistersNothing() async {
        let harness = AppModelHarness(configured: false)
        harness.model.start()
        await harness.settle()
        #expect(harness.model.gate == .configurationMissing)
        #expect(harness.registeredTokens.isEmpty)
        #expect(harness.fakes.session.calls.count("start") == 0)
    }

    @Test func launchGateRouteForcesTheGate() async {
        let harness = AppModelHarness(route: "sign-in")
        harness.model.start()
        await harness.settle()
        #expect(harness.model.gate == .signIn)
    }

    @Test func settingsDriveAppearance() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        #expect(harness.model.colorScheme == nil)
        await harness.fakes.settings.update { $0.appearance = .dark }
        #expect(await harness.until { harness.model.colorScheme == .dark })
    }
}

@MainActor
struct AppModelPushTests {
    @Test func primerShowsOnceAfterFirstSignInAndNotNowIsQuiet() async {
        let harness = AppModelHarness(authorization: .notDetermined, primerSeen: false)
        await harness.startSignedIn()
        #expect(harness.model.gate == .notificationPrimer)
        #expect(harness.registeredTokens.isEmpty)
        harness.model.choosePrimer(.notNow)
        #expect(await harness.until { harness.model.gate == nil })
        await harness.settle()
        #expect(harness.authorizer.requests == [.provisional])
        #expect(harness.model.systemNotificationStatus == .deliveredQuietly)
        #expect(harness.registeredTokens == ["fcm-token"])
    }

    @Test func registersOnceAfterSignInWithTheStoredPreferences() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        let registrations = harness.fakes.push.registrations.get()
        #expect(registrations.map(\.token) == ["fcm-token"])
        #expect(registrations.first?.preferences == harness.fakes.settings.currentSettings.notifications)
    }

    @Test func deniedPermissionNeverRegistersAndSettingsSaysSo() async {
        let harness = AppModelHarness(authorization: .denied)
        await harness.startSignedIn()
        #expect(harness.registeredTokens.isEmpty)
        #expect(harness.model.systemNotificationStatus == .offInSystemSettings)
        #expect(harness.model.gate == nil)
    }

    @Test func signOutUnregistersOnceThroughTheSession() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        harness.model.push(.settings)
        harness.model.signOut()
        #expect(await harness.until { harness.model.gate == .signIn })
        await harness.settle()
        #expect(harness.fakes.session.calls.count("signOut") == 1)
        #expect(harness.fakes.push.unregisterCount.get() == 1)
        #expect(harness.model.gate == .signIn)
        #expect(harness.model.navigation == NavigationState())
    }

    @Test func foregroundChatPushIsHiddenOnlyWhenTheDataLayerSaysSo() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        let push = PushPayload.chat(ChatPush(conversationID: 7, messageID: 1))
        #expect(harness.model.presentationDecision(for: push).showBanner)
        await harness.fakes.environment.messages.open(conversationId: 7)
        #expect(harness.model.presentationDecision(for: push) == .suppressed)
        harness.fakes.realtime.drop()
        #expect(harness.model.presentationDecision(for: push).showBanner)
        harness.fakes.realtime.connect()
        harness.model.scenePhaseChanged(to: .background)
        #expect(await harness.until { harness.model.presentationDecision(for: push).showBanner })
        harness.model.scenePhaseChanged(to: .active)
        #expect(await harness.until { harness.model.presentationDecision(for: push) == .suppressed })
        await harness.fakes.environment.messages.close(conversationId: 7)
        #expect(harness.model.presentationDecision(for: push).showBanner)
    }

    @Test func inAppBannersSwitchOffKeepsPushesInTheListOnly() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        await harness.fakes.settings.update { $0.notifications.inAppBanners = false }
        _ = await harness.until { !harness.model.settings.notifications.inAppBanners }
        let decision = harness.model.presentationDecision(for: .meeting(eventID: "evt_1"))
        #expect(decision == PresentationDecision(showBanner: false, showInList: true, playSound: false))
    }

    @Test func tapBeforeSignInOpensAfterAuthentication() async throws {
        let harness = AppModelHarness(scenario: .signedOut)
        harness.model.start()
        await harness.settle()
        let event = NotificationResponseEvent(
            key: "req-1:open",
            actionIdentifier: NotificationActionID.open,
            payload: .chat(ChatPush(conversationID: 7, messageID: 9312)),
            userText: nil
        )
        await harness.model.handle(event)
        #expect(harness.model.navigation.path(for: .chat).isEmpty)
        try await harness.signIn()
        #expect(harness.model.navigation.selectedTab == .chat)
        #expect(harness.model.navigation.path(for: .chat) == [.conversation(conversationID: 7, targetMessageID: 9312)])
        // The same response delivered again does not navigate twice.
        harness.model.navigation = NavigationState()
        await harness.model.handle(event)
        #expect(harness.model.navigation.path(for: .chat).isEmpty)
    }

    @Test func replyAndMarkReadGoToTheDataLayer() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        let push = PushPayload.chat(ChatPush(conversationID: 7, messageID: 9312))
        await harness.model.handle(
            NotificationResponseEvent(
                key: "a",
                actionIdentifier: NotificationActionID.reply,
                payload: push,
                userText: "on it"
            )
        )
        let threadReply = PushPayload.chat(ChatPush(conversationID: 7, messageID: 9331, threadRootMessageID: 9330))
        await harness.model.handle(
            NotificationResponseEvent(
                key: "b",
                actionIdentifier: NotificationActionID.reply,
                payload: threadReply,
                userText: "same"
            )
        )
        await harness.model.handle(
            NotificationResponseEvent(
                key: "c",
                actionIdentifier: NotificationActionID.markRead,
                payload: push,
                userText: nil
            )
        )
        // A thread reply also goes through the fake's outbox, which records `send:`.
        let calls = harness.fakes.chat.calls.all.filter { $0.hasPrefix("send:") || $0.hasPrefix("reply:") }
        #expect(calls == ["send:7", "reply:9330", "send:7"])
        #expect(harness.fakes.chat.calls.count("markRead:7") == 1)
    }

    @Test func replyBeforeSignInIsDropped() async {
        let harness = AppModelHarness(scenario: .signedOut)
        harness.model.start()
        await harness.settle()
        let push = PushPayload.chat(ChatPush(conversationID: 7, messageID: 9312))
        await harness.model.handle(
            NotificationResponseEvent(
                key: "a",
                actionIdentifier: NotificationActionID.reply,
                payload: push,
                userText: "hi"
            )
        )
        #expect(harness.fakes.chat.calls.count("send:") == 0)
    }
}

@MainActor
struct AppModelNavigationTests {
    @Test func launchRouteOpensOnSignIn() async {
        let harness = AppModelHarness(route: "settings-notifications")
        await harness.startSignedIn()
        #expect(harness.model.navigation.path(for: .today) == [.settings, .notificationSettings])
    }

    @Test func newChatSheetOpensTheConversationOnChat() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        harness.model.presentNewChat()
        #expect(harness.model.navigation.sheet == .newChat)
        harness.model.openConversationFromSheet(42)
        #expect(harness.model.navigation.sheet == nil)
        #expect(harness.model.navigation.selectedTab == .chat)
        #expect(harness.model.navigation.visibleConversationID == 42)
    }

    @Test func invalidLinksAreIgnored() async throws {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        harness.model.handle(url: try link("https://example.com/chats/7"))
        harness.model.handle(url: try link("waivera://chats/0"))
        #expect(harness.model.navigation == NavigationState())
    }

    @Test func chatAlertBannerOpensItsThreadAndClears() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        let alert = ChatAlert(
            conversationId: 7,
            messageId: 9331,
            reason: .threadReply,
            title: .person(name: "Priya Raman"),
            preview: "Same here",
            destination: .thread(rootMessageId: 9330, conversationId: 7, targetMessageId: 9331)
        )
        harness.fakes.alerts.emit(alert)
        #expect(await harness.until { harness.model.chatAlert == alert })
        harness.model.openChatAlert()
        #expect(harness.model.chatAlert == nil)
        #expect(
            harness.model.navigation.path(for: .chat) == [
                .conversation(conversationID: 7, targetMessageID: nil),
                .thread(rootMessageID: 9330, conversationID: 7, targetMessageID: 9331),
            ]
        )
    }

    @Test func connectionBannerFollowsTheHubAndRetries() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        #expect(harness.model.connectionBanner == .hidden)
        harness.fakes.realtime.drop(attempt: 2)
        #expect(await harness.until { harness.model.connectionBanner == .reconnecting(attempt: 2) })
        harness.model.retryRealtime()
        #expect(await harness.until { harness.model.connectionBanner == .hidden })
        #expect(harness.fakes.realtime.log.retries == 1)
    }
}
