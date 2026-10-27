import Foundation
import WaiveraNotifications
import WaiveraNotificationsLive

extension UserNotificationsAuthorizer: NotificationAuthorizing {}

/// Chooses the live data layer or the fake server. The fake path exists only in DEBUG builds and
/// only when launched with `-WaiveraFakeServer`.
enum CompositionRoot {
    /// `liveTokenSource` is the FCM token source; it is used only by the live data layer.
    static func makeEnvironment(
        launch: LaunchOptions,
        configuration: AppConfiguration,
        liveTokenSource: any PushTokenSource
    ) -> AppEnvironment {
        #if DEBUG
            if launch.usesFakeServer {
                return FakeServerEnvironment.make()
            }
        #endif
        #if canImport(WaiveraData)
            if let live = DataLayerBridge.makeLiveEnvironment(
                configuration: configuration,
                tokenSource: liveTokenSource
            ) {
                return live
            }
        #endif
        return unconfigured()
    }

    /// No API configuration: the app shows sign-in and never calls the network or registers push.
    private static func unconfigured() -> AppEnvironment {
        AppEnvironment(
            session: StaticSessionGateway(.signedOut),
            preferences: StaticPreferencesGateway(),
            hub: StaticHubStatus(isConnected: false),
            chatActions: NoChatActions(),
            registerPush: { _ in },
            unregisterPush: {},
            tokenSource: SilentTokenSource(),
            authorizer: UserNotificationsAuthorizer(),
            primerStore: PrimerSeenStore()
        )
    }
}
