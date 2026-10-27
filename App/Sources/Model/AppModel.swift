import Observation
import SwiftUI
import UIKit
import WaiveraDesign
import WaiveraNotifications
import WaiveraNotificationsLive
import WaiveraRouting

/// The shell's single source of truth: session gate, navigation, notification routing and push
/// registration. Feature state lives in feature models, never here.
@Observable
final class AppModel {
    var navigation = NavigationState()
    private(set) var session: ShellSession = .loading
    private(set) var preferences = ShellPreferences()
    /// `nil` until the system has answered, so the primer never flashes.
    private(set) var authorization: NotificationAuthorization?
    private(set) var hasSeenPrimer: Bool

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let launch: LaunchOptions
    @ObservationIgnored private let pushCoordinator: PushRegistrationCoordinator
    @ObservationIgnored private var tapRouter = NotificationTapRouter()
    @ObservationIgnored private var isSceneActive = true
    @ObservationIgnored private var started = false
    @ObservationIgnored private var registrationDebounce: Task<Void, Never>?
    /// Debounce for bursts of preference toggles (09-push §5 gap 4).
    @ObservationIgnored private let registrationDebounceDelay: Duration = .milliseconds(400)

    init(environment: AppEnvironment, launch: LaunchOptions) {
        self.environment = environment
        self.launch = launch
        hasSeenPrimer = environment.primerStore.hasSeen
        pushCoordinator = PushRegistrationCoordinator(
            register: environment.registerPush,
            unregister: environment.unregisterPush
        )
    }

    // MARK: Derived state

    /// The screen shown instead of the tabs, or `nil` for the tab shell.
    var gate: GateScreen? {
        if case .gate(let forced) = launch.route?.target {
            return forced
        }
        switch session {
        case .loading: return .loading
        case .signedOut: return .signIn
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

    var colorScheme: ColorScheme? {
        switch launch.appearance ?? preferences.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var systemNotificationStatus: SystemNotificationStatus {
        NotificationPermissionPolicy.status(for: authorization ?? .notDetermined)
    }

    var userDisplayName: String { session.user?.displayName ?? "" }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        if launch.disablesAnimations {
            UIView.setAnimationsEnabled(false)
        }
        observeSession()
        observePreferences()
        observeTokens()
        Task { await refreshAuthorization() }
    }

    func scenePhaseChanged(isActive: Bool) {
        let becameActive = isActive && !isSceneActive
        isSceneActive = isActive
        if becameActive {
            Task {
                await refreshAuthorization()
                await pushCoordinator.appBecameActive()
            }
        } else if !isActive, !session.isSignedIn {
            // Leaving the app before finishing sign-in abandons a held notification tap.
            tapRouter.discardPending()
        }
    }

    private func observeSession() {
        let stream = environment.session.states()
        Task {
            for await state in stream {
                await sessionChanged(to: state)
            }
        }
    }

    private func observePreferences() {
        let stream = environment.preferences.values()
        Task {
            for await value in stream {
                preferencesChanged(to: value)
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

    private func sessionChanged(to newState: ShellSession) async {
        let wasSignedIn = session.isSignedIn
        session = newState
        if newState.isSignedIn, !wasSignedIn {
            if let launchDestination = launch.route?.destination {
                navigation.open(launchDestination)
            }
            if let held = tapRouter.didAuthenticate() {
                navigation.open(held)
            }
            await pushCoordinator.didSignIn()
        } else if !newState.isSignedIn, wasSignedIn {
            navigation = NavigationState()
        }
    }

    private func preferencesChanged(to newValue: ShellPreferences) {
        let previous = preferences
        preferences = newValue
        HapticPlayer.shared.isEnabled = newValue.hapticsEnabled
        guard previous.pushRegistrationFingerprint != newValue.pushRegistrationFingerprint else { return }
        registrationDebounce?.cancel()
        let coordinator = pushCoordinator
        let delay = registrationDebounceDelay
        registrationDebounce = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await coordinator.preferencesChanged()
        }
    }

    private func refreshAuthorization() async {
        let status = await environment.authorizer.currentAuthorization()
        authorization = status
        await pushCoordinator.authorizationChanged(status)
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

    /// Foreground presentation for a push (called by `NotificationCenterDelegate`).
    func presentationDecision(for payload: PushPayload) -> PresentationDecision {
        let visible = isSceneActive && gate == nil ? navigation.visibleConversationID : nil
        let context = ForegroundContext(
            isHubConnected: environment.hub.isConnected,
            visibleConversationID: visible,
            inAppBannersEnabled: preferences.inAppBannersEnabled,
            soundEnabled: preferences.soundEnabled
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
            guard session.isSignedIn else { return }
            await environment.chatActions.reply(
                conversationID: conversationID,
                threadRootMessageID: threadRootMessageID,
                text: text
            )
        case .markRead(let conversationID, let messageID):
            guard session.isSignedIn else { return }
            await environment.chatActions.markRead(conversationID: conversationID, messageID: messageID)
            await DeliveredNotifications.removeAll(conversationID: conversationID)
        case .none:
            break
        }
    }

    func choosePrimer(_ choice: PrimerChoice) {
        environment.primerStore.markSeen()
        hasSeenPrimer = true
        Task {
            let status = await environment.authorizer.request(NotificationPermissionPolicy.request(for: choice))
            authorization = status
            await pushCoordinator.authorizationChanged(status)
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

    /// Unregisters the push token before the session clears (privacy fix, 08 §9).
    func signOut() {
        let coordinator = pushCoordinator
        let session = environment.session
        Task {
            await coordinator.prepareForSignOut()
            await session.signOut()
        }
    }
}
