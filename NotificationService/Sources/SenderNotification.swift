import Foundation
import Intents
import UserNotifications
import WaiveraNotifications

/// Turns a chat alert into a communication notification, so iOS draws the sender's image in
/// place of the app icon (with the icon as a small badge), as Android does.
enum SenderNotification {
    static func content(_ base: UNNotificationContent, sender: ChatSender, image: Data?) -> UNNotificationContent {
        let person = INPerson(
            personHandle: INPersonHandle(value: sender.userID, type: .unknown),
            nameComponents: nil,
            displayName: sender.name,
            image: image.map { INImage(imageData: $0) },
            contactIdentifier: nil,
            customIdentifier: sender.userID
        )
        // No message text in the intent: it is donated to the system, and bodies never leave the alert.
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: nil,
            speakableGroupName: nil,
            conversationIdentifier: "chat-\(sender.conversationID)",
            serviceName: nil,
            sender: person,
            attachments: nil
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate(completion: nil)
        return (try? base.updating(from: intent)) ?? base
    }
}
