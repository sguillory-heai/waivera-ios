import Foundation
import WaiveraData
import WaiveraNotifications

/// Reads and requests the system notification permission.
protocol NotificationAuthorizing {
    func currentAuthorization() async -> NotificationAuthorization
    func request(_ request: AuthorizationRequest) async -> NotificationAuthorization
}

/// Everything the shell runs on, chosen once by `CompositionRoot`.
struct AppEnvironment {
    /// The live or fake repositories. `nil` when the build has no API configuration; the app
    /// then shows the configuration-missing gate and never calls the network.
    let data: DataEnvironment?
    /// FCM registration tokens (Firebase in live builds, silent otherwise).
    let tokenSource: any PushTokenSource
    let authorizer: any NotificationAuthorizing
    let primerStore: PrimerSeenStore
    /// Whether a signed-out device still has an FCM token to delete (AS-02).
    var pendingInvalidation: any PendingInvalidationStore = PendingInvalidationDefaults()
}

/// Emits no token: simulators without push, unconfigured Firebase, the fake server.
/// `nonisolated` because the app target defaults to the main actor and `PushTokenSource` is a
/// nonisolated `Sendable` protocol.
nonisolated struct SilentTokenSource: PushTokenSource {
    func tokens() -> AsyncStream<String> {
        AsyncStream { _ in }
    }
}

/// Reports a fixed authorization and never shows the system prompt (UI tests, fake server).
struct StaticAuthorizer: NotificationAuthorizing {
    let status: NotificationAuthorization

    func currentAuthorization() async -> NotificationAuthorization { status }
    func request(_ request: AuthorizationRequest) async -> NotificationAuthorization { status }
}
