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

    /// The FCM registration-token calls the app relies on. Firebase 13 deprecates them in favour
    /// of installation-ID registration, which sprout_api cannot send to yet: it delivers to FCM
    /// registration tokens (docs/architecture/app-shell.md, Firebase). Calling them through this
    /// protocol keeps that decision in one place; drop it when the API moves to installation IDs.
    nonisolated protocol FCMRegistrationTokens {
        func token() async throws -> String
        func deleteToken() async throws
    }

    nonisolated extension Messaging: FCMRegistrationTokens {}

    /// FCM registration tokens: the current one at start-up and every rotation.
    /// Never logs the token (AGENTS.md safety rules).
    final class FirebaseTokenSource: NSObject, PushTokenSource, MessagingDelegate {
        private let stream: AsyncStream<String>
        private let continuation: AsyncStream<String>.Continuation

        /// Only assigns stored properties, so it needs no actor (`NSObject.init` is nonisolated).
        override nonisolated init() {
            let pair = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
            stream = pair.stream
            continuation = pair.continuation
            super.init()
        }

        /// Call after `FirebaseBootstrap.configureIfPossible`. Main actor because the bootstrap
        /// flag is main-actor state; the class itself is nonisolated for `PushTokenSource`.
        @MainActor func activate() {
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
            let tokens: some FCMRegistrationTokens = Messaging.messaging()
            try await tokens.deleteToken()
            let fresh = try await tokens.token()
            if !fresh.isEmpty { continuation.yield(fresh) }
        }

        nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
            guard let fcmToken, !fcmToken.isEmpty else { return }
            continuation.yield(fcmToken)
        }
    }
#endif
