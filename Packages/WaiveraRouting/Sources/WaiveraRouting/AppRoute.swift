/// The three bottom tabs, in order (PLAN.md: Today-first navigation; Tasks joins in phase 4).
public enum AppTab: String, CaseIterable, Codable, Hashable, Sendable {
    case today
    case chat
    case schedule
}

/// Every pushed screen. Routes carry ids only; screens load their own data.
/// Avatar-menu destinations (profile, people, bookmarks, settings) push onto whichever tab is
/// selected, so they have no fixed tab.
public enum AppRoute: Codable, Hashable, Sendable {
    // Today
    case activity
    // Chat
    case conversation(conversationID: Int, targetMessageID: Int?)
    case thread(rootMessageID: Int, conversationID: Int?, targetMessageID: Int?)
    // Schedule
    case calendarEvent(eventID: String)
    // Avatar menu
    case profile
    case organization
    case people
    case person(userID: String)
    case bookmarks
    case settings
    case notificationSettings
    case appearanceSettings
    case accountSettings

    /// The conversation this screen shows, used by the foreground presentation rule.
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

    public static func calendarEvent(_ eventID: String) -> Destination {
        Destination(tab: .schedule, path: [.calendarEvent(eventID: eventID)])
    }
}
