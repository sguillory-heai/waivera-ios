import ChatFeature
import ScheduleFeature
import SwiftUI
import TodayFeature
import WaiveraDesign
import WaiveraRouting

/// Each tab's root screen. Every root draws the hero bar with the signed-in avatar, which opens
/// the account menu: the shell passes `presentAccountMenu` to each one, and `MainTabView` also
/// provides it through `waiveraAccountMenu` (with the avatar photo) for any bar not given one.
struct TabRootView: View {
    @Bindable var model: AppModel
    let tab: AppTab

    var body: some View {
        switch tab {
        case .today:
            TodayView(
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: $1)) },
                onOpenThread: { model.push(.thread(rootMessageID: $0, conversationID: $1, targetMessageID: $2)) },
                onOpenEvent: { model.push(.calendarEvent(eventID: $0)) },
                onOpenSchedule: { model.select(.schedule) },
                onOpenActivity: { model.push(.activity) },
                onOpenAccount: { model.presentAccountMenu() }
            )
        case .chat:
            ConversationListView(
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: nil)) },
                onOpenPerson: { model.push(.person(userID: $0)) },
                // The hero bar's "+".
                onNewChat: { model.presentNewChat() },
                accountName: model.userDisplayName,
                onAccount: { model.presentAccountMenu() }
            )
        case .schedule:
            ScheduleView(
                onOpenEvent: { model.push(.calendarEvent(eventID: $0)) },
                // "Send wishes" on a celebration card opens the chat it started.
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: nil)) },
                onOpenAccount: { model.presentAccountMenu() }
            )
        }
    }
}
