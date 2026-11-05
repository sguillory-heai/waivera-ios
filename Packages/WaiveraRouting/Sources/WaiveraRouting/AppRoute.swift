/// The bottom tabs, in order, as on Android: Today, Chat, Schedule, Tasks.
public enum AppTab: String, CaseIterable, Codable, Hashable, Sendable {
    case today
    case chat
    case schedule
    case tasks
}

/// Every pushed screen. Routes carry ids only; screens load their own data.
/// Avatar-menu destinations (profile, people, bookmarks, settings) push onto whichever tab is
/// selected, so they have no fixed tab.
public enum AppRoute: Codable, Hashable, Sendable {
    // Today
    case activity
    /// The notifications inbox (the web bell), from Today's bell and inbox pushes.
    case notices
    // Chat
    case conversation(conversationID: Int, targetMessageID: Int?)
    case thread(rootMessageID: Int, conversationID: Int?, targetMessageID: Int?)
    /// A group's members, opened from the "N members" line in its header. Pushed over the
    /// conversation it belongs to.
    case groupMembers(conversationID: Int)
    // Schedule
    case calendarEvent(eventID: String)
    // Tasks
    /// `taskID` is the server's numeric task id, not the "ORG-123" key.
    case task(taskID: Int)
    /// One of a task's files in the read-only viewer.
    case taskFile(taskID: Int, attachmentID: Int)
    /// Change requests waiting on the person and their own.
    case requests
    /// A participant's read-only profile; `participantID` is the server's participant id.
    case participant(participantID: Int)
    // Avatar menu
    case profile
    case organization
    case people
    case person(userID: String)
    case bookmarks
    case settings
    case notificationSettings
    case appearanceSettings
    /// The voluntary password change, pushed from Settings → Security.
    case changePassword

    /// The conversation this screen shows, used by the foreground presentation rule. The members
    /// screen shows no messages, so a message there still raises its alert.
    public var conversationID: Int? {
        switch self {
        case .conversation(let conversationID, _): conversationID
        case .thread(_, let conversationID, _): conversationID
        default: nil
        }
    }
}

/// Modal sheets the router can present over a tab.
public enum AppSheet: String, Codable, Hashable, Sendable, Identifiable {
    case newChat

    public var id: String { rawValue }
}

/// Where a deep link, push tap or launch argument wants to go.
public struct Destination: Equatable, Sendable {
    /// `nil` keeps the selected tab (avatar-menu destinations).
    public var tab: AppTab?
    /// The full stack to show on that tab. Empty means the tab's root.
    public var path: [AppRoute]
    public var sheet: AppSheet?

    public init(tab: AppTab?, path: [AppRoute] = [], sheet: AppSheet? = nil) {
        self.tab = tab
        self.path = path
        self.sheet = sheet
    }

    public static let today = Destination(tab: .today)
    public static let inbox = Destination(tab: .chat)
    public static let schedule = Destination(tab: .schedule)
    public static let tasks = Destination(tab: .tasks)
    public static let notices = Destination(tab: .today, path: [.notices])
    public static let requests = Destination(tab: .tasks, path: [.requests])

    public static func task(_ taskID: Int) -> Destination {
        Destination(tab: .tasks, path: [.task(taskID: taskID)])
    }

    /// A conversation opened from outside the app: the back button returns to the inbox.
    public static func conversation(_ conversationID: Int, targetMessageID: Int? = nil) -> Destination {
        Destination(tab: .chat, path: [.conversation(conversationID: conversationID, targetMessageID: targetMessageID)])
    }

    /// A thread opened from outside the app. When the conversation is known it sits under the
    /// thread so back goes thread → conversation → inbox.
    public static func thread(rootMessageID: Int, conversationID: Int?, targetMessageID: Int? = nil) -> Destination {
        var path: [AppRoute] = []
        if let conversationID {
            path.append(.conversation(conversationID: conversationID, targetMessageID: nil))
        }
        path.append(
            .thread(rootMessageID: rootMessageID, conversationID: conversationID, targetMessageID: targetMessageID)
        )
        return Destination(tab: .chat, path: path)
    }

    /// A group's members over its conversation, so back goes members → conversation → inbox.
    public static func groupMembers(_ conversationID: Int) -> Destination {
        Destination(
            tab: .chat,
            path: [
                .conversation(conversationID: conversationID, targetMessageID: nil),
                .groupMembers(conversationID: conversationID),
            ]
        )
    }

    public static func calendarEvent(_ eventID: String) -> Destination {
        Destination(tab: .schedule, path: [.calendarEvent(eventID: eventID)])
    }
}
