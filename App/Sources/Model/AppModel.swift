import Observation
import SwiftUI
import UIKit
import WaiveraAPI
import WaiveraData
import WaiveraDesign
import WaiveraNotifications
import WaiveraNotificationsLive
import WaiveraRouting

/// The shell's single source of truth: session gate, navigation, notification routing, push
/// token hand-off and the app-wide banners. Feature state lives in feature models, never here.
@Observable
final class AppModel {
    var navigation = NavigationState()
    private(set) var session: SessionState
    private(set) var settings: AppSettings
    /// `nil` until the system has answered, so the primer never flashes.
    private(set) var authorization: NotificationAuthorization?
    private(set) var hasSeenPrimer: Bool
    /// The quiet reconnecting / offline banner (05 §2).
    private(set) var connectionBanner: ConnectionBanner = .hidden
    /// The in-app banner for a message outside the visible conversation (05 §9).
    private(set) var chatAlert: ChatAlert?
    /// Set once the sign-in screen has been shown, so a sign-in attempt keeps showing it while
    /// the backend login runs, but a cold start with a stored session shows the loading screen.
    private(set) var hasShownSignIn = false

    @ObservationIgnored let dataEnvironment: DataEnvironment?
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let launch: LaunchOptions
    @ObservationIgnored private let pushCoordinator: PushRegistrationCoordinator
    @ObservationIgnored private var tapRouter = NotificationTapRouter()
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var reportedForeground: Bool?
    @ObservationIgnored private var started = false

    init(environment: AppEnvironment, launch: LaunchOptions) {
        self.environment = environment
        self.launch = launch
        let data = environment.data
        dataEnvironment = data
        session = data?.session.currentState ?? .configurationMissing
        // Read synchronously so the stored appearance applies before the first frame (08 §7).
        settings = data?.settings.currentSettings ?? AppSettings()
        hasSeenPrimer = environment.primerStore.hasSeen
        pushCoordinator = PushRegistrationCoordinator { token in
            guard let data else { return }
            // The repository debounces, skips an unchanged fingerprint and retries.
            await data.push.register(token: token, preferences: data.settings.currentSettings.notifications)
        }
    }

    // MARK: Derived state

    /// The screen shown instead of the tabs, or `nil` for the tab shell.
    var gate: GateScreen? {
        if case .gate(let forced) = launch.route?.target {
            return forced
        }
        switch session {
        case .loading: return .loading
        case .bootstrapping: return hasShownSignIn ? .signIn : .loading
        case .signedOut: return .signIn
        case .bootstrapFailed: return .bootstrapFailed
        case .configurationMissing: return .configurationMissing
        case .passwordChangeRequired: return .passwordChange
        case .onboardingRequired: return .onboardingRequired
        case .signedIn:
            guard let authorization else { return nil }
            let showsPrimer = NotificationPermissionPolicy.shouldShowPrimer(
                authorization: authorization,
                hasSeenPrimer: hasSeenPrimer
            )
            return showsPrimer ? .notificationPrimer : nil
        }
    }

    /// Client-owned copy for the bootstrap-failed gate; never server text.
    var bootstrapFailureMessage: String {
        if case .bootstrapFailed(let error) = session {
            return error.userMessage
        }
        return WaiveraError.invalidResponse.userMessage
    }

    var colorScheme: ColorScheme? {
        switch launch.appearance ?? settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var systemNotificationStatus: SystemNotificationStatus {
        NotificationPermissionPolicy.status(for: authorization ?? .notDetermined)
    }

    var userDisplayName: String {
        guard let user = session.user else { return "" }
        return user.displayName ?? user.asChatUser.fullName ?? ""
    }

    // MARK: Lifecycle

    /// Call once, when the app finishes launching.
    func start() {
        guard !started else { return }
        started = true
        if launch.disablesAnimations {
            UIView.setAnimationsEnabled(false)
        }
        observeTokens()
        Task { await refreshAuthorization() }
        guard let data = dataEnvironment else { return }
        observe(data.session.states()) { model, state in await model.sessionChanged(to: state) }
        observe(data.settings.settings()) { model, value in model.settingsChanged(to: value) }
        observe(data.realtimeStatus.banner()) { model, banner in model.connectionBanner = banner }
        observe(data.alerts.alerts()) { model, alert in model.alertArrived(alert) }
        Task { await data.launch() }
    }

    /// Every scene phase change. Realtime runs only while the app is not in the background;
    /// `.inactive` (Control Center, the app switcher, a system sheet) keeps the hub connected.
    func scenePhaseChanged(to phase: ScenePhase) {
        let isActive = phase == .active
        let becameActive = isActive && !isSceneActive
        isSceneActive = isActive
        let isForeground = phase != .background
        if let data = dataEnvironment, reportedForeground != isForeground {
            reportedForeground = isForeground
            Task { await data.setForeground(isForeground) }
        }
        if becameActive {
            let coordinator = pushCoordinator
            Task {
                await refreshAuthorization()
                await coordinator.appBecameActive()
            }
        } else if phase == .background, !session.isSignedIn {
            // Leaving the app before finishing sign-in abandons a held notification tap.
            tapRouter.discardPending()
        }
    }

    private func observe<Value: Sendable>(
        _ stream: AsyncStream<Value>,
        _ apply: @escaping @MainActor (AppModel, Value) async -> Void
    ) {
        Task { [weak self] in
            for await value in stream {
                guard let self else { return }
                await apply(self, value)
            }
        }
    }

    private func observeTokens() {
        let stream = environment.tokenSource.tokens()
        let coordinator = pushCoordinator
        Task {
            for await token in stream {
                await coordinator.tokenChanged(token)
            }
        }
    }

    private func sessionChanged(to newState: SessionState) async {
        let previous = session
        session = newState
        switch newState {
        case .signedOut: hasShownSignIn = true
        case .signedIn: hasShownSignIn = false
        default: break
        }
        let switchedAccount = previous.isSignedIn && newState.isSignedIn && previous.user?.id != newState.user?.id
        if switchedAccount || (!previous.isSignedIn && newState.isSignedIn) {
            if switchedAccount {
                navigation = NavigationState()
                chatAlert = nil
            }
            if let launchDestination = launch.route?.destination {
                navigation.open(launchDestination)
            }
            if let held = tapRouter.didAuthenticate() {
                navigation.open(held)
            }
            await pushCoordinator.didSignIn()
        } else if previous.isSignedIn, !newState.isSignedIn {
            navigation = NavigationState()
            chatAlert = nil
            await pushCoordinator.didSignOut()
        }
    }

    private func settingsChanged(to newValue: AppSettings) {
        settings = newValue
        HapticPlayer.shared.isEnabled = newValue.hapticsEnabled
        // Notification switch changes re-register inside the data layer (debounced there).
    }

    private func refreshAuthorization() async {
        let status = await environment.authorizer.currentAuthorization()
        authorization = status
        await pushCoordinator.authorizationChanged(status)
    }

    // MARK: Banners

    private func alertArrived(_ alert: ChatAlert) {
        // The data layer already applied the in-app banner switch and presence (G-09).
        guard gate == nil else { return }
        chatAlert = alert
    }

    func openChatAlert() {
        guard let alert = chatAlert else { return }
        chatAlert = nil
        navigation.open(Self.destination(for: alert.destination))
    }

    /// Clears `alert` if it is still the one shown (a newer alert keeps its own timer).
    func dismissChatAlert(_ alert: ChatAlert) {
        guard chatAlert == alert else { return }
        chatAlert = nil
    }

    func retryRealtime() {
        guard let data = dataEnvironment else { return }
        Task { await data.realtimeStatus.retryNow() }
    }

    static func destination(for destination: ChatDestination) -> Destination {
        switch destination {
        case .conversation(let id, let targetMessageId):
            .conversation(id, targetMessageID: targetMessageId)
        case .thread(let rootMessageId, let conversationId, let targetMessageId):
            .thread(rootMessageID: rootMessageId, conversationID: conversationId, targetMessageID: targetMessageId)
        }
    }

    // MARK: Navigation

    func push(_ route: AppRoute) {
        navigation.push(route)
    }

    func select(_ tab: AppTab) {
        navigation.select(tab)
    }

    func presentNewChat() {
        navigation.sheet = .newChat
    }

    func dismissSheet() {
        navigation.sheet = nil
    }

    /// From the new-chat sheet: close it and open the conversation on the Chat tab.
    func openConversationFromSheet(_ conversationID: Int) {
        navigation.sheet = nil
        navigation.open(.conversation(conversationID), origin: .inApp)
    }

    func handle(url: URL) {
        guard let destination = DeepLink.destination(from: url) else { return }
        // Links are not deduplicated: the same link tapped twice should work twice.
        let key = "url:\(UUID().uuidString)"
        if let now = tapRouter.handle(key: key, destination: destination, isAuthenticated: session.isSignedIn) {
            navigation.open(now)
        }
    }

    // MARK: Notifications

    /// Foreground presentation for a push (called by `NotificationCenterDelegate`). Whether a
    /// chat push is hidden is the data layer's call (`shouldPresentForegroundPush`).
    func presentationDecision(for payload: PushPayload) -> PresentationDecision {
        let shouldPresent = dataEnvironment?.alerts.shouldPresentForegroundPush(conversationId: payload.conversationID)
        let context = ForegroundContext(
            isConversationLive: payload.isChat && shouldPresent == false,
            inAppBannersEnabled: settings.notifications.inAppBanners,
            soundEnabled: settings.notifications.sound
        )
        return ForegroundPresentationPolicy.decide(for: payload, context: context)
    }

    func handle(_ event: NotificationResponseEvent) async {
        switch event.action {
        case .open(let destination):
            let now = tapRouter.handle(key: event.key, destination: destination, isAuthenticated: session.isSignedIn)
            if let now {
                navigation.open(now)
            }
        case .reply(let conversationID, let threadRootMessageID, let text):
            guard let data = signedInData else { return }
            // Queued in the outbox: retried, persisted and confirmed like an in-app send.
            if let threadRootMessageID {
                await data.threads.reply(
                    text: text,
                    attachment: nil,
                    rootMessageId: threadRootMessageID,
                    conversationId: conversationID
                )
            } else {
                await data.messages.send(text: text, attachment: nil, conversationId: conversationID)
            }
        case .markRead(let conversationID, _):
            guard let data = signedInData else { return }
            await data.messages.markRead(conversationId: conversationID)
            await DeliveredNotifications.removeAll(conversationID: conversationID)
        case .none:
            break
        }
    }

    /// The data layer, only while its session is signed in (read directly, not from the
    /// observed copy, so an action delivered right after launch sees the latest state).
    private var signedInData: DataEnvironment? {
        guard let data = dataEnvironment, data.session.currentState.isSignedIn else { return nil }
        return data
    }

    func choosePrimer(_ choice: PrimerChoice) {
        environment.primerStore.markSeen()
        hasSeenPrimer = true
        let authorizer = environment.authorizer
        let coordinator = pushCoordinator
        Task {
            let status = await authorizer.request(NotificationPermissionPolicy.request(for: choice))
            authorization = status
            await coordinator.authorizationChanged(status)
        }
    }

    /// Settings → Notifications "Turn on" / "Turn on alerts".
    func requestNotificationPermission() {
        if systemNotificationStatus == .offInSystemSettings {
            openSystemNotificationSettings()
        } else {
            choosePrimer(.enable)
        }
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Session

    /// The session's single sign-out path: it unregisters push and stops realtime while
    /// requests still authenticate, then clears Firebase and the caches (01 §6, 08 §9).
    func signOut() {
        guard let data = dataEnvironment else { return }
        Task { await data.session.signOut() }
    }

    /// Bootstrap-failed gate: run the backend login again without signing out.
    func retryBootstrap() {
        guard let data = dataEnvironment else { return }
        Task { await data.session.retryBootstrap() }
    }
}
