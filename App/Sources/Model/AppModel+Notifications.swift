import Foundation
import UIKit
import WaiveraData
import WaiveraNotifications
import WaiveraNotificationsLive
import WaiveraRouting

// MARK: Notifications

extension AppModel {
    /// Foreground presentation for a push (called by `NotificationCenterDelegate`). Whether a
    /// chat push is hidden is the data layer's call (`shouldPresentForegroundPush`); nothing is
    /// shown while signed out, since it would be the previous person's message.
    func presentationDecision(for payload: PushPayload) -> PresentationDecision {
        let shouldPresent = dataEnvironment?.alerts.shouldPresentForegroundPush(conversationId: payload.conversationID)
        let context = ForegroundContext(
            isConversationLive: payload.isChat && shouldPresent == false,
            inAppBannersEnabled: settings.notifications.inAppBanners,
            soundEnabled: settings.notifications.sound,
            isSignedIn: dataEnvironment?.session.currentState.isSignedIn ?? false
        )
        return ForegroundPresentationPolicy.decide(for: payload, context: context)
    }

    func handle(_ event: NotificationResponseEvent) async {
        switch event.action {
        case .open(let destination):
            let now = tapRouter.handle(key: event.key, destination: destination, isAuthenticated: session.isSignedIn)
            if let now {
                navigation.open(now)
            }
        case .reply(let conversationID, let threadRootMessageID, let text):
            guard let data = await settledSignedInData() else { return }
            // Queued in the outbox: retried, persisted and confirmed like an in-app send.
            if let threadRootMessageID {
                await data.threads.reply(
                    text: text,
                    attachment: nil,
                    rootMessageId: threadRootMessageID,
                    conversationId: conversationID
                )
            } else {
                await data.messages.send(text: text, attachment: nil, conversationId: conversationID)
            }
        case .markRead(let conversationID, _):
            guard let data = await settledSignedInData() else { return }
            // A failed mark keeps the notification, so it can be tried again from there.
            guard (try? await data.messages.markRead(conversationId: conversationID)) != nil else { return }
            await DeliveredNotifications.removeAll(conversationID: conversationID)
        case .none:
            break
        }
    }

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
        environment.primerStore.markSeen()
        hasSeenPrimer = true
        let authorizer = environment.authorizer
        let coordinator = pushCoordinator
        Task {
            let status = await authorizer.request(NotificationPermissionPolicy.request(for: choice))
            authorization = status
            await coordinator.authorizationChanged(status)
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
