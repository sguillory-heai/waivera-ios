import Foundation
import WaiveraData

enum AppStrings {
    static var loading: String { String(localized: "app.loading") }
    static var tabToday: String { String(localized: "app.tab.today") }
    static var tabChat: String { String(localized: "app.tab.chat") }
    static var tabSchedule: String { String(localized: "app.tab.schedule") }
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
