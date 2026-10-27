import Foundation
import WaiveraNotifications
import WaiveraNotificationsLive

extension UserNotificationsAuthorizer: NotificationAuthorizing {}

/// Chooses what the app runs on, in this order:
/// 1. the fake server: DEBUG builds launched with `-WaiveraFakeServer` (`LaunchOptions.fakeScenario`);
/// 2. the live data layer, when the `.xcconfig` values are present;
/// 3. unconfigured: the configuration-missing gate, no network and no push.
enum CompositionRoot {
    /// `liveTokenSource` is the FCM token source; only the live data layer uses it.
    static func makeEnvironment(
        launch: LaunchOptions,
        configuration: AppConfiguration,
        liveTokenSource: any PushTokenSource
    ) -> AppEnvironment {
        #if DEBUG
            if let scenario = launch.fakeScenario {
                return AppEnvironment(
                    data: DataLayerBridge.makeFakeEnvironment(scenario, webBaseURL: configuration.webBaseURL),
                    tokenSource: SilentTokenSource(),
                    // Permission counts as granted so UI tests never meet the system prompt.
                    authorizer: StaticAuthorizer(status: .authorized),
                    // A throwaway suite so fake runs never mark the real primer as seen.
                    primerStore: PrimerSeenStore(suiteName: "waivera.fake-server"),
                    pendingInvalidation: PendingInvalidationDefaults(suiteName: "waivera.fake-server")
                )
            }
        #endif
        let live = DataLayerBridge.makeLiveEnvironment(configuration: configuration)
        return AppEnvironment(
            data: live,
            tokenSource: live == nil ? SilentTokenSource() : liveTokenSource,
            authorizer: UserNotificationsAuthorizer(),
            primerStore: PrimerSeenStore()
        )
    }
}
