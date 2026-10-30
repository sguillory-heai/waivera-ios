import ChatFeature
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
    /// The gate a re-run of the backend login started from (bootstrap failed, onboarding,
    /// required password change). It stays on screen through `.bootstrapping`, so that screen
    /// keeps its busy state and its answer instead of flashing the loader or sign-in.
    private(set) var heldGate: GateScreen?
    /// Unread messages across every chat, for the Chat tab's count.
    private(set) var unreadTotal = 0
    /// The account menu sheet, opened from the avatar in a tab root's top bar.
    var isAccountMenuPresented = false
    /// A `waivera://` link arrived that the app cannot open; the tabs say so once (Android
    /// `unopenableLink`, UI2-22). A new value shows the snackbar again.
    private(set) var unopenableLink: UUID?

    @ObservationIgnored let dataEnvironment: DataEnvironment?
    @ObservationIgnored let environment: AppEnvironment
    @ObservationIgnored private let launch: LaunchOptions
    @ObservationIgnored let pushCoordinator: PushRegistrationCoordinator
    @ObservationIgnored var tapRouter = NotificationTapRouter()
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
        let tokenSource = environment.tokenSource
        pushCoordinator = PushRegistrationCoordinator(
            register: { token in
                guard let data else { return }
                // The repository debounces, skips an unchanged fingerprint and retries. A final
                // failure is thrown so the coordinator tries again on the next activation (IF-06).
                try await data.push.registerAndWait(
                    token: token,
                    preferences: data.settings.currentSettings.notifications
                )
            },
            invalidate: { try await tokenSource.invalidate() },
            pending: environment.pendingInvalidation
        )
    }

    // MARK: Derived state

    /// The screen shown instead of the tabs, or `nil` for the tab shell.
    var gate: GateScreen? {
        if case .gate(let forced) = launch.route?.target {
            return forced
        }
        return Self.sessionGate(for: session, hasShownSignIn: hasShownSignIn, heldGate: heldGate) ?? primerGate
    }

    /// The gate for every state but `signedIn`.
    static func sessionGate(
        for session: SessionState,
        hasShownSignIn: Bool,
        heldGate: GateScreen? = nil
    ) -> GateScreen? {
        switch session {
        case .loading: .loading
        case .bootstrapping: heldGate ?? (hasShownSignIn ? .signIn : .loading)
        case .signedOut: .signIn
        case .bootstrapFailed: .bootstrapFailed
        case .configurationMissing: .configurationMissing
        case .passwordChangeRequired: .passwordChange
        case .onboardingRequired: .onboardingRequired
        case .signedIn: nil
        }
    }

    /// The gate kept on screen when the session re-runs the backend login from `previous`.
    static func gateHeld(whileRebootstrappingFrom previous: SessionState) -> GateScreen? {
        switch previous {
        case .bootstrapFailed: .bootstrapFailed
        case .onboardingRequired: .onboardingRequired
        case .passwordChangeRequired: .passwordChange
        default: nil
        }
    }

    /// Signed in: the primer once, after the system has answered and before it was ever asked.
    private var primerGate: GateScreen? {
        guard let authorization else { return nil }
        let showsPrimer = NotificationPermissionPolicy.shouldShowPrimer(
            authorization: authorization,
            hasSeenPrimer: hasSeenPrimer
        )
        return showsPrimer ? .notificationPrimer : nil
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
        let coordinator = pushCoordinator
        Task {
            await coordinator.launched()
            await refreshAuthorization()
        }
        guard let data = dataEnvironment else { return }
        observe(data.session.states()) { model, state in await model.sessionChanged(to: state) }
        observe(data.settings.settings()) { model, value in model.settingsChanged(to: value) }
        observe(data.realtimeStatus.banner()) { model, banner in model.connectionBanner = banner }
        observe(data.alerts.alerts()) { model, alert in model.alertArrived(alert) }
        observe(data.conversations.totalUnread()) { model, total in model.unreadTotal = total }
        // Read on any surface, here or on the web, clears that chat's notifications (IF-07).
        observe(data.alerts.conversationsRead()) { _, conversationID in
            await DeliveredNotifications.removeAll(conversationID: conversationID)
        }
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
        if case .bootstrapping = newState {
            heldGate = Self.gateHeld(whileRebootstrappingFrom: previous) ?? heldGate
        } else {
            heldGate = nil
        }
        session = newState
        switch newState {
        case .signedOut:
            hasShownSignIn = true
            // Nothing of the previous person stays in Notification Center or the share folder
            // (AS-02, AS-10).
            DeliveredNotifications.removeEverything()
            AttachmentFiles.removeAll()
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
            if let held = tapRouter.didAuthenticate(accountSince: dataEnvironment?.session.accountSince) {
                navigation.open(held)
            }
            await pushCoordinator.didSignIn()
        } else if previous.isSignedIn, !newState.isSignedIn {
            // A tap held from this session never opens for whoever signs in next (IS-07).
            tapRouter.discardPending()
            navigation = NavigationState()
            chatAlert = nil
            isAccountMenuPresented = false
            unopenableLink = nil
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
}

// MARK: Banners

extension AppModel {
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
}

// MARK: Navigation

extension AppModel {
    func push(_ route: AppRoute) {
        navigation.push(route)
    }

    func pop() {
        navigation.pop()
    }

    func select(_ tab: AppTab) {
        navigation.select(tab)
    }

    func presentAccountMenu() {
        isAccountMenuPresented = true
    }

    /// From the account menu: close it, then open `route` over the current tab (Android
    /// `openFromAccountMenu`), so back returns to the tab the menu was opened on.
    func openFromAccountMenu(_ route: AppRoute) {
        isAccountMenuPresented = false
        navigation.push(route)
    }

    /// The "That link can't be opened" snackbar went away.
    func dismissUnopenableLink(_ id: UUID) {
        if unopenableLink == id { unopenableLink = nil }
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
        guard let destination = DeepLink.destination(from: url) else {
            // The stack stays where it is, but the tap is acknowledged.
            unopenableLink = UUID()
            return
        }
        // Links are not deduplicated: the same link tapped twice should work twice.
        let key = "url:\(UUID().uuidString)"
        // A link has no delivery date: it is the current person's own tap.
        if let now = tapRouter.handle(key: key, destination: destination, isAuthenticated: session.isSignedIn) {
            navigation.open(now)
        }
    }
}

// MARK: Session

extension AppModel {
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
