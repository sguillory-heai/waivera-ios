import Foundation
import UIKit
import WaiveraData
import WaiveraNotifications
import WaiveraNotificationsLive
import WaiveraRouting

// MARK: Notifications

extension AppModel {
    /// Foreground presentation for a push (called by `NotificationCenterDelegate`). Whether a
    /// chat push is hidden is the data layer's call, per surface (IF-02): a thread reply only
    /// while its thread is on screen, a root message only while its conversation is. Nothing
    /// is shown while signed out, since it would be the previous person's message.
    func presentationDecision(for payload: PushPayload) -> PresentationDecision {
        var conversationLive = false
        var threadLive = false
        if case .chat(let chat) = payload, let alerts = dataEnvironment?.alerts {
            if chat.isThreadReply {
                threadLive = !alerts.shouldPresentForegroundPush(
                    conversationId: chat.conversationID,
                    threadRootMessageId: chat.threadRootMessageID
                )
            } else {
                conversationLive = !alerts.shouldPresentForegroundPush(
                    conversationId: chat.conversationID,
                    threadRootMessageId: nil
                )
            }
        }
        let context = ForegroundContext(
            isConversationLive: conversationLive,
            inAppBannersEnabled: settings.notifications.inAppBanners,
            soundEnabled: settings.notifications.sound,
            isSignedIn: dataEnvironment?.session.currentState.isSignedIn ?? false,
            isThreadLive: threadLive
        )
        return ForegroundPresentationPolicy.decide(for: payload, context: context)
    }

    /// A notification response. Responses to a notification delivered before the current
    /// account signed in belong to someone else on this device and are dropped (IS-07).
    func handle(_ event: NotificationResponseEvent) async {
        switch event.action {
        case .open(let destination):
            let now = tapRouter.handle(
                key: event.key,
                destination: destination,
                isAuthenticated: session.isSignedIn,
                deliveredAt: event.deliveredAt
            )
            if let now, event.belongsToAccount(since: dataEnvironment?.session.accountSince) {
                navigation.open(now)
            }
        case .reply(let conversationID, let threadRootMessageID, let text):
            guard let data = await settledSignedInData(), event.belongsToAccount(since: data.session.accountSince)
            else { return }
            await sendNotificationReply(
                text: text,
                conversationID: conversationID,
                threadRootMessageID: threadRootMessageID,
                data: data
            )
        case .markRead(let conversationID, _):
            guard let data = await settledSignedInData(), event.belongsToAccount(since: data.session.accountSince)
            else { return }
            // A failed mark keeps the notification, so it can be tried again from there.
            guard (try? await data.messages.markRead(conversationId: conversationID)) != nil else { return }
            await DeliveredNotifications.removeAll(conversationID: conversationID)
        case .none:
            break
        }
    }

    /// IF-03: iOS gives a notification action a few seconds and may suspend the app as soon as
    /// the handler returns. The reply is on disk before the first attempt, and a background task
    /// keeps the app running for the send itself, up to `replyTimeout`. If it is still not
    /// confirmed, a local notification says so; the outbox keeps it for the next launch.
    private func sendNotificationReply(
        text: String,
        conversationID: Int,
        threadRootMessageID: Int?,
        data: DataEnvironment
    ) async {
        let activity = BackgroundActivity(name: "notification-reply")
        defer { activity.end() }
        let outcome = await data.messages.sendAndWait(
            text: text,
            conversationId: conversationID,
            threadRootMessageId: threadRootMessageID,
            timeout: Self.replyTimeout
        )
        switch outcome {
        case .sent, .dropped:
            break
        case .queued, .failed:
            await DeliveredNotifications.postReplyNotSent(
                conversationID: conversationID,
                threadRootMessageID: threadRootMessageID,
                title: AppStrings.replyNotSentTitle,
                body: AppStrings.replyNotSentBody
            )
        }
    }

    /// Within the roughly 30 s a background task gets, leaving time to post the notice.
    static let replyTimeout: Duration = .seconds(20)

    /// The data layer once its session is signed in. A Reply or Mark read that cold-launched
    /// the app arrives while the stored session is still loading or bootstrapping, so this
    /// waits (up to `timeout`) for the session to settle instead of dropping the action. The
    /// state is read from the data layer, not the observed copy, which may not have caught up.
    func settledSignedInData(timeout: Duration = .seconds(10)) async -> DataEnvironment? {
        guard let data = dataEnvironment else { return nil }
        if data.session.currentState.isSignedIn { return data }
        let session = data.session
        let signedIn = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await state in session.states() {
                    switch state {
                    case .loading, .bootstrapping: continue
                    default: return state.isSignedIn
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        return signedIn ? data : nil
    }

    func choosePrimer(_ choice: PrimerChoice) {
        markPrimerSeen()
        let authorizer = environment.authorizer
        Task {
            let status = await authorizer.request(NotificationPermissionPolicy.request(for: choice))
            await authorizationAnswered(status)
        }
    }

    /// Settings → Notifications "Turn on" / "Turn on alerts".
    func requestNotificationPermission() {
        if systemNotificationStatus == .offInSystemSettings {
            openSystemNotificationSettings()
        } else {
            choosePrimer(.enable)
        }
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// One `UIApplication` background task, ended exactly once: by its owner, or by iOS when the
/// time runs out.
final class BackgroundActivity {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
