import ChatFeature
import ScheduleFeature
import SwiftUI
import TodayFeature
import WaiveraDesign
import WaiveraRouting

/// Each tab's root screen. Their hero bars show the signed-in avatar and open the account menu
/// through `waiveraAccountMenu`, which `MainTabView` provides above the tabs.
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
                onOpenActivity: { model.push(.activity) }
            )
        case .chat:
            ConversationListView(
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: nil)) },
                onOpenPerson: { model.push(.person(userID: $0)) },
                onNewChat: { model.presentNewChat() }
            )
        case .schedule:
            ScheduleView(onOpenEvent: { model.push(.calendarEvent(eventID: $0)) })
        }
    }
}
