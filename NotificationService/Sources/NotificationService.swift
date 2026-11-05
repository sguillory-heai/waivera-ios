import Foundation
import UserNotifications
import WaiveraNotifications

/// Shows the sender on chat pushes the way Messages does (WAIV-2939): the person's photo,
/// or their tile (`AvatarTiles`, the app's photo-less look) when they have none or the photo
/// does not arrive in time. Every other push, and bot messages, pass through unchanged.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    // `@unchecked`: every stored property is read and written under `lock`.
    private let lock = NSLock()
    private var pending: Pending?
    private var work: Task<Void, Never>?

    private struct Pending {
        let content: UNNotificationContent
        let sender: ChatSender
        let deliver: (UNNotificationContent) -> Void
    }

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let content = request.content
        guard let sender = ChatSender.from(userInfo: content.userInfo, title: content.title) else {
            contentHandler(content)
            return
        }
        lock.withLock { pending = Pending(content: content, sender: sender, deliver: contentHandler) }
        let task = Task { [weak self] in
            let photo = await SenderPhoto.load(userID: sender.userID)
            self?.finish(photo: photo)
        }
        lock.withLock { work = task }
    }

    /// Out of time: show the tile now rather than the bare alert.
    override func serviceExtensionTimeWillExpire() {
        lock.withLock { work }?.cancel()
        finish(photo: nil)
    }

    /// Delivers once, whichever of the photo and the deadline comes first.
    private func finish(photo: Data?) {
        let taken = lock.withLock { () -> Pending? in
            defer { self.pending = nil }
            return self.pending
        }
        guard let taken else { return }
        let image = photo ?? SenderTile.image(name: taken.sender.name)
        taken.deliver(SenderNotification.content(taken.content, sender: taken.sender, image: image))
    }
}
