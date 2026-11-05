import Foundation
import WaiveraData

enum AppStrings {
    static var loading: String { String(localized: "app.loading") }
    static var tabToday: String { String(localized: "app.tab.today") }
    static var tabChat: String { String(localized: "app.tab.chat") }
    static var tabSchedule: String { String(localized: "app.tab.schedule") }
    static var tabTasks: String { String(localized: "app.tab.tasks") }
    static var accountFallback: String { String(localized: "app.menu.accountFallback") }
    static var viewProfile: String { String(localized: "app.menu.viewProfile") }
    static var menuPeople: String { String(localized: "app.menu.people") }
    static var menuBookmarks: String { String(localized: "app.menu.bookmarks") }
    static var menuSettings: String { String(localized: "app.menu.settings") }
    static var linkUnopenable: String { String(localized: "app.link.unopenable") }

    /// VoiceOver value on the Chat tab: "4 unread".
    static func tabUnread(_ count: Int) -> String {
        String(localized: "app.tab.unread \(count)")
    }

    static var alertOpen: String { String(localized: "app.alert.open") }
    static var privacyCover: String { String(localized: "app.privacyCover") }
    static var replyNotSentTitle: String { String(localized: "app.reply.notSent.title") }
    static var replyNotSentBody: String { String(localized: "app.reply.notSent.body") }

    /// "Priya Raman: can you cover Friday?", or the reason when previews are off.
    static func chatAlert(_ alert: ChatAlert) -> String {
        let title = alert.title.map(conversationTitle) ?? String(localized: "app.alert.title.someone")
        let body = alert.preview ?? reason(alert.reason)
        return String(localized: "app.alert.message \(title) \(body)")
    }

    static var chatAlertNow: String { String(localized: "app.alert.now") }
    static var alertDismiss: String { String(localized: "app.alert.dismiss") }

    /// The card's headline: the person in a one-to-one chat, the channel or group otherwise.
    static func chatAlertTitle(_ alert: ChatAlert) -> String {
        if case .person = alert.title, let sender = alert.sender { return sender.name }
        return alert.title.map(conversationTitle) ?? alert.sender?.name ?? String(localized: "app.alert.title.someone")
    }

    /// The name the tile's initials and colour come from when there's no photo.
    static func chatAlertAvatarName(_ alert: ChatAlert) -> String {
        alert.sender?.name ?? chatAlertTitle(alert)
    }

    /// The message, led by the sender's name in a channel or group.
    static func chatAlertBody(_ alert: ChatAlert) -> AttributedString {
        let text = AttributedString(alert.preview ?? reason(alert.reason))
        guard let sender = alert.sender, chatAlertTitle(alert) != sender.name else { return text }
        var name = AttributedString(String(localized: "app.alert.sender \(sender.name)"))
        name.inlinePresentationIntent = .stronglyEmphasized
        return name + text
    }

    private static func conversationTitle(_ title: ConversationTitle) -> String {
        switch title {
        case .channel(let name?):
            String(localized: "app.alert.title.channel \(name)")
        case .channel(nil):
            String(localized: "app.alert.title.channelUnnamed")
        case .bot:
            String(localized: "app.alert.title.bot")
        case .person(let name):
            name ?? String(localized: "app.alert.title.someone")
        case .group(let firstName?, let otherCount):
            String(localized: "app.alert.title.group \(firstName) \(otherCount)")
        case .group(nil, _), .untitled:
            String(localized: "app.alert.title.conversation")
        }
    }

    private static func reason(_ reason: ChatAlert.Reason) -> String {
        switch reason {
        case .mention: String(localized: "app.alert.reason.mention")
        case .threadReply: String(localized: "app.alert.reason.threadReply")
        case .message: String(localized: "app.alert.reason.message")
        }
    }
}
