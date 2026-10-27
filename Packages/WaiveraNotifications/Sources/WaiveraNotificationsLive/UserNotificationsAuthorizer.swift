#if canImport(UserNotifications) && canImport(UIKit)
    import UserNotifications
    import WaiveraNotifications

    /// Reads and requests notification permission. Requests only ever come from the primer's
    /// buttons or the Settings row, never on launch.
    public struct UserNotificationsAuthorizer: Sendable {
        public init() {}

        public func currentAuthorization() async -> NotificationAuthorization {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return Self.map(settings.authorizationStatus)
        }

        /// Requests permission and returns the resulting status. Errors read as the status after the call.
        public func request(_ request: AuthorizationRequest) async -> NotificationAuthorization {
            var options: UNAuthorizationOptions = [.alert, .sound, .badge]
            if request == .provisional {
                options.insert(.provisional)
            }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: options)
            return await currentAuthorization()
        }

        static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
            switch status {
            case .notDetermined: .notDetermined
            case .denied: .denied
            case .authorized: .authorized
            case .provisional: .provisional
            case .ephemeral: .ephemeral
            @unknown default: .denied
            }
        }
    }
#endif
