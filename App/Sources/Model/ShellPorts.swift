import Foundation
import WaiveraNotifications

/// The shell's view of the signed-in user. Identity is the backend user id, never the Firebase uid.
struct ShellUser: Equatable, Sendable {
    let id: String
    let displayName: String
}

/// Session states the auth gate renders (mapped from `SessionRepository` by `DataLayerBridge`).
enum ShellSession: Equatable, Sendable {
    case loading
    case signedOut
    case passwordChangeRequired
    case onboardingRequired
    case signedIn(ShellUser)

    var user: ShellUser? {
        if case .signedIn(let user) = self { return user }
        return nil
    }

    var isSignedIn: Bool { user != nil }
}

enum AppearancePreference: String, Sendable {
    case system
    case light
    case dark
}

/// The preferences the shell itself applies. Feature screens read the rest from `SettingsRepository`.
struct ShellPreferences: Equatable, Sendable {
    var appearance: AppearancePreference = .system
    var hapticsEnabled = true
    var inAppBannersEnabled = true
    var soundEnabled = true
    /// Changes whenever a value sent with the push registration changes, so the shell
    /// re-registers (preferences ride on registration, push.md §1).
    var pushRegistrationFingerprint = ""
}

/// Session source and sign-out. Main-actor isolated by the app's default isolation.
protocol SessionGateway: AnyObject {
    func states() -> AsyncStream<ShellSession>
    func signOut() async
}

protocol PreferencesGateway: AnyObject {
    func values() -> AsyncStream<ShellPreferences>
}

/// Whether the chat hub is connected right now (presentation rule).
protocol HubStatusGateway: AnyObject {
    var isConnected: Bool { get }
}

/// Notification actions that act on chat without opening the app UI.
protocol ChatActionsGateway: AnyObject {
    func reply(conversationID: Int, threadRootMessageID: Int?, text: String) async
    func markRead(conversationID: Int, messageID: Int?) async
}

protocol NotificationAuthorizing {
    func currentAuthorization() async -> NotificationAuthorization
    func request(_ request: AuthorizationRequest) async -> NotificationAuthorization
}

/// Everything the shell needs from the data layer and the platform, chosen by `CompositionRoot`.
struct AppEnvironment {
    let session: any SessionGateway
    let preferences: any PreferencesGateway
    let hub: any HubStatusGateway
    let chatActions: any ChatActionsGateway
    let registerPush: PushRegistrationCoordinator.Register
    let unregisterPush: PushRegistrationCoordinator.Unregister
    let tokenSource: any PushTokenSource
    let authorizer: any NotificationAuthorizing
    let primerStore: PrimerSeenStore
}
