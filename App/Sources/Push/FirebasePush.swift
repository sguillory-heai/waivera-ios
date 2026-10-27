#if canImport(FirebaseMessaging)
    import FirebaseCore
    import FirebaseMessaging
    import Foundation
    import WaiveraNotifications

    /// Configures Firebase for Messaging only, from `.xcconfig` values (no GoogleService-Info.plist
    /// in git). Skipped entirely when values are absent, so unconfigured builds never touch Firebase.
    enum FirebaseBootstrap {
        private(set) static var isConfigured = false

        static func configureIfPossible(_ configuration: AppConfiguration.FirebaseMessaging?) {
            guard !isConfigured, let configuration else { return }
            let options = FirebaseOptions(googleAppID: configuration.appID, gcmSenderID: configuration.senderID)
            options.apiKey = configuration.apiKey
            options.projectID = configuration.projectID
            FirebaseApp.configure(options: options)
            isConfigured = true
        }

        /// Hands the APNs device token to FCM. Swizzling is off (`FirebaseAppDelegateProxyEnabled`).
        static func setAPNSToken(_ deviceToken: Data) {
            guard isConfigured else { return }
            Messaging.messaging().apnsToken = deviceToken
        }
    }

    /// FCM registration tokens: the current one at start-up and every rotation.
    /// Never logs the token (AGENTS.md safety rules).
    final class FirebaseTokenSource: NSObject, PushTokenSource, MessagingDelegate {
        private let stream: AsyncStream<String>
        private let continuation: AsyncStream<String>.Continuation

        override init() {
            let pair = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
            stream = pair.stream
            continuation = pair.continuation
            super.init()
        }

        /// Call after `FirebaseBootstrap.configureIfPossible`.
        func activate() {
            guard FirebaseBootstrap.isConfigured else { return }
            Messaging.messaging().delegate = self
        }

        nonisolated func tokens() -> AsyncStream<String> {
            stream
        }

        /// Sign-out: deletes the token so a registration the server kept reaches nobody, then
        /// asks for a fresh one, which the coordinator holds until the next sign-in.
        nonisolated func invalidate() async throws {
            guard await MainActor.run(body: { FirebaseBootstrap.isConfigured }) else { return }
            try await Messaging.messaging().deleteToken()
            let fresh = try await Messaging.messaging().token()
            if !fresh.isEmpty { continuation.yield(fresh) }
        }

        nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
            guard let fcmToken, !fcmToken.isEmpty else { return }
            continuation.yield(fcmToken)
        }
    }
#endif
