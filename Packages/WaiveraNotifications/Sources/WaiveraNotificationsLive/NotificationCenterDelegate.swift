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

        // The completion-handler forms, not the async ones: iOS runs UIKit snapshot work when the
        // handler is called, and an async delegate method returns on a background thread, which
        // aborts the app when a tap opens it from the background. The handlers are called on main.

        public func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            let payload = PushPayloadParser.parse(userInfo: notification.request.content.userInfo)
            let done = MainThreadCompletion(completionHandler)
            Task { @MainActor in
                let decision = presenter(payload)
                done.call(Self.options(for: decision))
            }
        }

        public func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            let request = response.notification.request
            let event = NotificationResponseEvent(
                key: "\(request.identifier):\(response.actionIdentifier)",
                actionIdentifier: response.actionIdentifier,
                payload: PushPayloadParser.parse(userInfo: request.content.userInfo),
                userText: (response as? UNTextInputNotificationResponse)?.userText,
                deliveredAt: response.notification.date
            )
            let done = MainThreadCompletion(completionHandler)
            Task { @MainActor in
                await onResponse(event)
                done.call(())
            }
        }

        static func options(for decision: PresentationDecision) -> UNNotificationPresentationOptions {
            var options: UNNotificationPresentationOptions = []
            if decision.showBanner { options.insert(.banner) }
            if decision.showInList { options.insert(.list) }
            if decision.playSound { options.insert(.sound) }
            return options
        }
    }

    /// Carries a UserNotifications completion handler into a main-actor task. `@unchecked`: the
    /// handler is only ever called once, from the main actor.
    private struct MainThreadCompletion<Value>: @unchecked Sendable {
        private let handler: (Value) -> Void

        init(_ handler: @escaping (Value) -> Void) {
            self.handler = handler
        }

        init(_ handler: @escaping () -> Void) where Value == Void {
            self.handler = { _ in handler() }
        }

        @MainActor
        func call(_ value: Value) {
            handler(value)
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

        /// A read elsewhere (`chat.read`): clears the conversation's alerts, or one thread's, that
        /// arrived at or before `readAt`, so a late read never clears newer messages.
        public static func removeRead(conversationID: Int, threadRootMessageID: Int?, readAt: Date?) async {
            let center = UNUserNotificationCenter.current()
            let thread = NotificationCategories.threadIdentifier(conversationID: conversationID)
            let identifiers = await center.deliveredNotifications()
                .filter { delivered in
                    guard delivered.request.content.threadIdentifier == thread else { return false }
                    if let readAt, delivered.date > readAt { return false }
                    guard let threadRootMessageID else { return true }
                    let root = delivered.request.content.userInfo["threadRootMessageId"].map { "\($0)" }
                    return root == String(threadRootMessageID)
                }
                .map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        /// An inbox notification (or with `nil` every one) was read: its alert leaves Notification Center.
        public static func removeInbox(notificationID: String?) async {
            let center = UNUserNotificationCenter.current()
            let identifiers = await center.deliveredNotifications()
                .filter { delivered in
                    let info = delivered.request.content.userInfo
                    guard (info["type"] as? String) == "notification" else { return false }
                    guard let notificationID else { return true }
                    return (info["notificationId"] as? String) == notificationID
                }
                .map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        /// A notification reply that could not be sent in the time iOS gave the app (IF-03). It is
        /// still queued and goes out on the next launch; this says so, and a tap opens the chat.
        /// The text is the caller's localized copy, never the reply itself.
        public static func postReplyNotSent(
            conversationID: Int,
            threadRootMessageID: Int?,
            title: String,
            body: String
        ) async {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.threadIdentifier = NotificationCategories.threadIdentifier(conversationID: conversationID)
            var userInfo: [String: String] = ["type": "chat", "conversationId": String(conversationID)]
            if let threadRootMessageID {
                userInfo["threadRootMessageId"] = String(threadRootMessageID)
            }
            content.userInfo = userInfo
            let request = UNNotificationRequest(
                identifier: "reply-not-sent-\(conversationID)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }

        /// Sign-out: nothing of the previous person stays in Notification Center.
        public static func removeEverything() {
            let center = UNUserNotificationCenter.current()
            center.removeAllDeliveredNotifications()
            center.removeAllPendingNotificationRequests()
        }
    }
#endif
