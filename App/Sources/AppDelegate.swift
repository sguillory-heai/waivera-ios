import UIKit
import UserNotifications
import WaiveraNotifications
import WaiveraNotificationsLive

/// Owns the app model and the platform hooks SwiftUI does not expose: the notification center
/// delegate (set before launch finishes so cold-start taps arrive) and APNs registration.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model: AppModel
    private var notificationDelegate: NotificationCenterDelegate?
    #if canImport(FirebaseMessaging)
        private let tokenSource: FirebaseTokenSource
    #endif

    override init() {
        let launch = LaunchOptions.current
        let configuration = AppConfiguration.main
        let liveTokenSource: any PushTokenSource
        #if canImport(FirebaseMessaging)
            if !launch.usesFakeServer {
                FirebaseBootstrap.configureIfPossible(configuration.firebaseMessaging)
            }
            let firebaseTokens = FirebaseTokenSource()
            tokenSource = firebaseTokens
            liveTokenSource = firebaseTokens
        #else
            liveTokenSource = SilentTokenSource()
        #endif
        model = AppModel(
            environment: CompositionRoot.makeEnvironment(
                launch: launch,
                configuration: configuration,
                liveTokenSource: liveTokenSource
            ),
            launch: launch
        )
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let model = model
        let delegate = NotificationCenterDelegate(
            presenter: { payload in model.presentationDecision(for: payload) },
            onResponse: { event in await model.handle(event) }
        )
        UNUserNotificationCenter.current().delegate = delegate
        notificationDelegate = delegate
        NotificationCategoryRegistrar.register()
        #if canImport(FirebaseMessaging)
            tokenSource.activate()
        #endif
        model.start()
        // Does not prompt. Fails quietly until the aps-environment entitlement exists (pending
        // Apple Developer account access); Firebase is skipped when unconfigured.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseMessaging)
            FirebaseBootstrap.setAPNSToken(deviceToken)
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Expected on simulators without push and before the push entitlement exists. Nothing is
        // logged: the error can carry device identifiers.
    }
}
