import AuthFeature
import ChatFeature
import ProfileFeature
import ScheduleFeature
import SettingsFeature
import SwiftUI
import TodayFeature
import WaiveraRouting

/// Resolves every `AppRoute` to its feature entry view. The only place features meet.
struct RouteDestinationView: View {
    @Bindable var model: AppModel
    let route: AppRoute

    // One case per route by design; splitting it would scatter the route table.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    var body: some View {
        switch route {
        case .activity:
            ActivityView(
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: $1)) },
                onOpenThread: { model.push(.thread(rootMessageID: $0, conversationID: $1, targetMessageID: $2)) }
            )
        case .conversation(let conversationID, let targetMessageID):
            ConversationView(
                conversationID: conversationID,
                targetMessageID: targetMessageID,
                onOpenThread: { rootID, messageID in
                    model.push(
                        .thread(rootMessageID: rootID, conversationID: conversationID, targetMessageID: messageID)
                    )
                },
                onOpenPerson: { model.push(.person(userID: $0)) },
                onOpenMembers: { model.push(.groupMembers(conversationID: $0)) }
            )
        case .groupMembers(let conversationID):
            GroupMembersView(
                channelID: conversationID,
                onOpenPerson: { model.push(.person(userID: $0)) },
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: nil)) }
            )
        case .thread(let rootMessageID, let conversationID, let targetMessageID):
            ThreadView(
                rootMessageID: rootMessageID,
                conversationID: conversationID,
                targetMessageID: targetMessageID,
                onOpenPerson: { model.push(.person(userID: $0)) }
            )
        case .calendarEvent(let eventID):
            CalendarEventView(
                eventID: eventID,
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: nil)) }
            )
        case .profile:
            ProfileView(onOpenOrganization: { model.push(.organization) }, onOpenSettings: { model.push(.settings) })
        case .organization:
            OrganizationView()
        case .people:
            PeopleView(onOpenPerson: { model.push(.person(userID: $0)) })
        case .person(let userID):
            PersonView(
                userID: userID,
                onOpenConversation: { model.push(.conversation(conversationID: $0, targetMessageID: nil)) }
            )
        case .bookmarks:
            BookmarksView(onOpenMessage: { conversationID, messageID, threadRootID in
                if let threadRootID {
                    model.push(
                        .thread(rootMessageID: threadRootID, conversationID: conversationID, targetMessageID: messageID)
                    )
                } else {
                    model.push(.conversation(conversationID: conversationID, targetMessageID: messageID))
                }
            })
        case .settings:
            SettingsView(
                onOpenNotifications: { model.push(.notificationSettings) },
                onOpenAppearance: { model.push(.appearanceSettings) },
                onOpenChangePassword: { model.push(.changePassword) },
                onSignOut: { model.signOut() }
            )
        case .notificationSettings:
            NotificationSettingsView(
                systemStatus: model.systemNotificationStatus,
                onRequestPermission: { model.requestNotificationPermission() },
                onOpenSystemSettings: { model.openSystemNotificationSettings() }
            )
        case .appearanceSettings:
            AppearanceSettingsView()
        case .changePassword:
            PasswordChangeView(onDone: { model.pop() })
        }
    }
}
