import Foundation
import Testing
import WaiveraNotifications
import WaiveraRouting

@testable import Waivera

/// Ordered record of what the shell asked the data layer to do.
@MainActor
final class CallLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }
}

@MainActor
final class RecordingSession: SessionGateway {
    private let log: CallLog
    private var continuation: AsyncStream<ShellSession>.Continuation?
    private var current: ShellSession

    init(_ initial: ShellSession, log: CallLog) {
        current = initial
        self.log = log
    }

    func states() -> AsyncStream<ShellSession> {
        let (stream, continuation) = AsyncStream<ShellSession>.makeStream()
        self.continuation = continuation
        continuation.yield(current)
        return stream
    }

    func signOut() async {
        log.append("session.signOut")
        emit(.signedOut)
    }

    func emit(_ state: ShellSession) {
        current = state
        continuation?.yield(state)
    }
}

@MainActor
final class MutablePreferences: PreferencesGateway {
    private var continuation: AsyncStream<ShellPreferences>.Continuation?

    func values() -> AsyncStream<ShellPreferences> {
        let (stream, continuation) = AsyncStream<ShellPreferences>.makeStream()
        self.continuation = continuation
        continuation.yield(ShellPreferences())
        return stream
    }

    func emit(_ value: ShellPreferences) {
        continuation?.yield(value)
    }
}

final class MutableHub: HubStatusGateway {
    var isConnected = true
}

final class RecordingChatActions: ChatActionsGateway {
    private let log: CallLog

    init(log: CallLog) {
        self.log = log
    }

    func reply(conversationID: Int, threadRootMessageID: Int?, text: String) async {
        log.append("reply \(conversationID) \(text)")
    }

    func markRead(conversationID: Int, messageID: Int?) async {
        log.append("markRead \(conversationID)")
    }
}

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

@MainActor
struct AppModelHarness {
    let log = CallLog()
    let session: RecordingSession
    let preferences = MutablePreferences()
    let hub = MutableHub()
    let authorizer: RecordingAuthorizer
    let model: AppModel

    init(
        session initial: ShellSession = .signedIn(ShellUser(id: "usr_alex_rivera", displayName: "Alex Rivera")),
        authorization: NotificationAuthorization = .authorized,
        token: String? = "fcm-token",
        route: String? = nil,
        primerSeen: Bool = true
    ) {
        let log = log
        session = RecordingSession(initial, log: log)
        authorizer = RecordingAuthorizer(status: authorization)
        let primerStore = PrimerSeenStore(suiteName: "waivera.tests.\(UUID().uuidString)")
        if primerSeen {
            primerStore.markSeen()
        }
        var launch = LaunchOptions()
        launch.route = route.flatMap(RouteCatalog.entry(named:))
        model = AppModel(
            environment: AppEnvironment(
                session: session,
                preferences: preferences,
                hub: hub,
                chatActions: RecordingChatActions(log: log),
                registerPush: { token in await log.append("register \(token)") },
                unregisterPush: { await log.append("unregister") },
                tokenSource: FixedTokens(token: token),
                authorizer: authorizer,
                primerStore: primerStore
            ),
            launch: launch
        )
    }

    /// Lets the model's observation tasks and the registration actor catch up.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(80))
    }
}

private func link(_ text: String) throws -> URL {
    try #require(URL(string: text))
}

@MainActor
struct AppModelTests {
    @Test func gateFollowsTheSession() async {
        let harness = AppModelHarness(session: .loading)
        #expect(harness.model.gate == .loading)
        harness.model.start()
        await harness.settle()
        #expect(harness.model.gate == .loading)
        harness.session.emit(.signedOut)
        await harness.settle()
        #expect(harness.model.gate == .signIn)
        harness.session.emit(.passwordChangeRequired)
        await harness.settle()
        #expect(harness.model.gate == .passwordChange)
        harness.session.emit(.onboardingRequired)
        await harness.settle()
        #expect(harness.model.gate == .onboardingRequired)
        harness.session.emit(.signedIn(ShellUser(id: "usr_1", displayName: "Priya Raman")))
        await harness.settle()
        #expect(harness.model.gate == nil)
        #expect(harness.model.userDisplayName == "Priya Raman")
    }

    @Test func primerShowsOnceAfterFirstSignInAndNotNowIsQuiet() async {
        let harness = AppModelHarness(authorization: .notDetermined, primerSeen: false)
        harness.model.start()
        await harness.settle()
        #expect(harness.model.gate == .notificationPrimer)
        #expect(!harness.log.entries.contains { $0.hasPrefix("register") })
        harness.model.choosePrimer(.notNow)
        await harness.settle()
        #expect(harness.model.gate == nil)
        #expect(harness.authorizer.requests == [.provisional])
        #expect(harness.model.systemNotificationStatus == .deliveredQuietly)
        #expect(harness.log.entries == ["register fcm-token"])
    }

    @Test func registersOnceAfterSignIn() async {
        let harness = AppModelHarness()
        harness.model.start()
        await harness.settle()
        #expect(harness.log.entries == ["register fcm-token"])
    }

    @Test func deniedPermissionNeverRegistersAndSettingsSaysSo() async {
        let harness = AppModelHarness(authorization: .denied)
        harness.model.start()
        await harness.settle()
        #expect(harness.log.entries.isEmpty)
        #expect(harness.model.systemNotificationStatus == .offInSystemSettings)
        #expect(harness.model.gate == nil)
    }

    @Test func signOutUnregistersBeforeTheSessionClears() async {
        let harness = AppModelHarness()
        harness.model.start()
        await harness.settle()
        harness.model.push(.settings)
        harness.model.signOut()
        await harness.settle()
        #expect(harness.log.entries == ["register fcm-token", "unregister", "session.signOut"])
        #expect(harness.model.gate == .signIn)
        #expect(harness.model.navigation == NavigationState())
    }

    @Test func tapBeforeSignInOpensAfterAuthentication() async {
        let harness = AppModelHarness(session: .signedOut)
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
        harness.session.emit(.signedIn(ShellUser(id: "usr_alex_rivera", displayName: "Alex Rivera")))
        await harness.settle()
        #expect(harness.model.navigation.selectedTab == .chat)
        #expect(harness.model.navigation.path(for: .chat) == [.conversation(conversationID: 7, targetMessageID: 9312)])
        // The same response delivered again does not navigate twice.
        harness.model.navigation = NavigationState()
        await harness.model.handle(event)
        #expect(harness.model.navigation.path(for: .chat).isEmpty)
    }

    @Test func replyAndMarkReadGoToTheDataLayer() async {
        let harness = AppModelHarness()
        harness.model.start()
        await harness.settle()
        let push = PushPayload.chat(ChatPush(conversationID: 7, messageID: 9312))
        await harness.model.handle(
            NotificationResponseEvent(
                key: "a",
                actionIdentifier: NotificationActionID.reply,
                payload: push,
                userText: "on it"
            )
        )
        await harness.model.handle(
            NotificationResponseEvent(
                key: "b",
                actionIdentifier: NotificationActionID.markRead,
                payload: push,
                userText: nil
            )
        )
        #expect(harness.log.entries.suffix(2) == ["reply 7 on it", "markRead 7"])
    }

    @Test func foregroundChatPushIsHiddenOnlyForTheVisibleConnectedConversation() async throws {
        let harness = AppModelHarness()
        harness.model.start()
        await harness.settle()
        harness.model.handle(url: try link("waivera://chats/7"))
        let push = PushPayload.chat(ChatPush(conversationID: 7, messageID: 1))
        #expect(harness.model.presentationDecision(for: push) == .suppressed)
        harness.hub.isConnected = false
        #expect(harness.model.presentationDecision(for: push).showBanner)
        harness.hub.isConnected = true
        harness.model.scenePhaseChanged(isActive: false)
        #expect(harness.model.presentationDecision(for: push).showBanner)
        harness.model.scenePhaseChanged(isActive: true)
        harness.model.select(.today)
        #expect(harness.model.presentationDecision(for: push).showBanner)
    }

    @Test func launchRouteOpensOnSignIn() async {
        let harness = AppModelHarness(route: "settings-notifications")
        harness.model.start()
        await harness.settle()
        #expect(harness.model.navigation.path(for: .today) == [.settings, .notificationSettings])
    }

    @Test func launchGateRouteForcesTheGate() async {
        let harness = AppModelHarness(route: "sign-in")
        harness.model.start()
        await harness.settle()
        #expect(harness.model.gate == .signIn)
    }

    @Test func preferenceBurstReRegistersOnce() async {
        let harness = AppModelHarness()
        harness.model.start()
        await harness.settle()
        for index in 1...3 {
            var value = ShellPreferences()
            value.pushRegistrationFingerprint = "v\(index)"
            harness.preferences.emit(value)
        }
        try? await Task.sleep(for: .milliseconds(600))
        #expect(harness.log.entries == ["register fcm-token", "register fcm-token"])
    }

    @Test func newChatSheetOpensTheConversationOnChat() async {
        let harness = AppModelHarness()
        harness.model.start()
        await harness.settle()
        harness.model.presentNewChat()
        #expect(harness.model.navigation.sheet == .newChat)
        harness.model.openConversationFromSheet(42)
        #expect(harness.model.navigation.sheet == nil)
        #expect(harness.model.navigation.selectedTab == .chat)
        #expect(harness.model.navigation.visibleConversationID == 42)
    }

    @Test func invalidLinksAreIgnored() async throws {
        let harness = AppModelHarness()
        harness.model.start()
        await harness.settle()
        harness.model.handle(url: try link("https://example.com/chats/7"))
        harness.model.handle(url: try link("waivera://chats/0"))
        #expect(harness.model.navigation == NavigationState())
    }
}
