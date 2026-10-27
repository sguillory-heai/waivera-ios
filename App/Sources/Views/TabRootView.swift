import ChatFeature
import ScheduleFeature
import SwiftUI
import TodayFeature
import WaiveraDesign
import WaiveraRouting

/// Each tab's root screen. Today and Chat carry the avatar menu in the top bar.
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
            .toolbar { avatarMenu }
        case .chat:
            ConversationListView(
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: nil)) },
                onOpenPerson: { model.push(.person(userID: $0)) },
                onNewChat: { model.presentNewChat() }
            )
            .toolbar { avatarMenu }
        case .schedule:
            ScheduleView(onOpenEvent: { model.push(.calendarEvent(eventID: $0)) })
        }
    }

    @ToolbarContentBuilder private var avatarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            AvatarMenuButton(
                name: model.userDisplayName,
                accessibilityLabel: AppStrings.accountMenu,
                items: [
                    AvatarMenuItem(id: "profile", title: AppStrings.menuProfile, systemImage: "person.crop.circle") {
                        model.push(.profile)
                    },
                    AvatarMenuItem(id: "people", title: AppStrings.menuPeople, systemImage: "person.2") {
                        model.push(.people)
                    },
                    AvatarMenuItem(id: "bookmarks", title: AppStrings.menuBookmarks, systemImage: "bookmark") {
                        model.push(.bookmarks)
                    },
                    AvatarMenuItem(id: "settings", title: AppStrings.menuSettings, systemImage: "gearshape") {
                        model.push(.settings)
                    },
                ]
            )
        }
    }
}
