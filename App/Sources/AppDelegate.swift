import UIKit
import UserNotifications
import WaiveraNotifications
import WaiveraNotificationsLive

/// Owns the app model and the platform hooks SwiftUI does not expose: the notification center
/// delegate (set before launch finishes so cold-start taps arrive) and APNs registration.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Built on first use rather than in an `init` override: `NSObject.init` is nonisolated and
    /// the model is main-actor state. The delegate adaptor and SwiftUI both use it on the main
    /// thread, and `didFinishLaunching` touches it before any notification response arrives.
    private(set) lazy var model: AppModel = makeModel()
    private var notificationDelegate: NotificationCenterDelegate?
    private var privacyCover: PrivacyCoverController?
    #if canImport(FirebaseMessaging)
        private var tokenSource: FirebaseTokenSource?
    #endif

    private func makeModel() -> AppModel {
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
        return AppModel(
            environment: CompositionRoot.makeEnvironment(
                launch: launch,
                configuration: configuration,
                liveTokenSource: liveTokenSource
            ),
            launch: launch
        )
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
            tokenSource?.activate()
        #endif
        model.start()
        privacyCover = PrivacyCoverController { [weak model] in model?.session.isSignedIn ?? false }
        // Does not prompt. Fails quietly until the aps-environment entitlement exists (pending
        // Apple Developer account access); Firebase is skipped when unconfigured.
        application.registerForRemoteNotifications()
        return true
    }

    /// The Keychain was locked when the session loaded (a push woke the app after a restart);
    /// load it now instead of treating the person as signed out (IS-03).
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        guard let data = model.dataEnvironment else { return }
        Task { await data.protectedDataDidBecomeAvailable() }
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
