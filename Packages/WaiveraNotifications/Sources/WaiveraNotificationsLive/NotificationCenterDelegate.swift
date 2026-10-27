#if canImport(UserNotifications) && canImport(UIKit)
    import Foundation
    import UserNotifications
    import WaiveraNotifications

    /// `UNUserNotificationCenterDelegate` that reduces every callback to Sendable values and hands
    /// them to main-actor closures owned by the app. Set it as the center's delegate before
    /// `application(_:didFinishLaunchingWithOptions:)` returns so cold-start taps are delivered.
    public final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
        // `@unchecked`: the only stored state is two immutable `@Sendable` closures.
        public typealias Presenter = @MainActor @Sendable (PushPayload) -> PresentationDecision
        public typealias ResponseHandler = @MainActor @Sendable (NotificationResponseEvent) async -> Void

        private let presenter: Presenter
        private let onResponse: ResponseHandler

        public init(presenter: @escaping Presenter, onResponse: @escaping ResponseHandler) {
            self.presenter = presenter
            self.onResponse = onResponse
        }

        public func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            let payload = PushPayloadParser.parse(userInfo: notification.request.content.userInfo)
            let decision = await presenter(payload)
            return Self.options(for: decision)
        }

        public func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            let request = response.notification.request
            let event = NotificationResponseEvent(
                key: "\(request.identifier):\(response.actionIdentifier)",
                actionIdentifier: response.actionIdentifier,
                payload: PushPayloadParser.parse(userInfo: request.content.userInfo),
                userText: (response as? UNTextInputNotificationResponse)?.userText,
                deliveredAt: response.notification.date
            )
            await onResponse(event)
        }

        static func options(for decision: PresentationDecision) -> UNNotificationPresentationOptions {
            var options: UNNotificationPresentationOptions = []
            if decision.showBanner { options.insert(.banner) }
            if decision.showInList { options.insert(.list) }
            if decision.playSound { options.insert(.sound) }
            return options
        }
    }

    /// Clears a conversation's notifications from Notification Center once it is read.
    public enum DeliveredNotifications {
        public static func removeAll(conversationID: Int) async {
            let center = UNUserNotificationCenter.current()
            let thread = NotificationCategories.threadIdentifier(conversationID: conversationID)
            let identifiers = await center.deliveredNotifications()
                .filter { $0.request.content.threadIdentifier == thread }
                .map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        /// Sign-out: nothing of the previous person stays in Notification Center.
        public static func removeEverything() {
            let center = UNUserNotificationCenter.current()
            center.removeAllDeliveredNotifications()
            center.removeAllPendingNotificationRequests()
        }
    }
#endif
