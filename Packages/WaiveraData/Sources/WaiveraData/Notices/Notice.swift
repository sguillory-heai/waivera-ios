import Foundation

/// A stored notification, the same list the web bell shows (`api/notifications`). The server
/// keeps them; the phone only shows and marks them read.
public struct Notice: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var kind: NoticeKind
    /// Title and message with the web's `{task}`/`{author}` placeholders already filled.
    public var title: String
    public var message: String
    public var createdAt: Date?
    public var isRead: Bool
    /// The task it is about, when it names one; opens the task.
    public var taskId: String?
    /// The calendar event it is about, when it names one; opens the event in the app.
    public var eventId: String?
    /// A web path (`/…`) for everything the app has no screen for, opened in the browser.
    public var webPath: String?
    /// A change request waiting on this person's review; opens Requests.
    public var opensRequests: Bool

    public init(
        id: String,
        kind: NoticeKind,
        title: String,
        message: String,
        createdAt: Date?,
        isRead: Bool,
        taskId: String? = nil,
        eventId: String? = nil,
        webPath: String? = nil,
        opensRequests: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.createdAt = createdAt
        self.isRead = isRead
        self.taskId = taskId
        self.eventId = eventId
        self.webPath = webPath
        self.opensRequests = opensRequests
    }

    /// Asks the person to do something, so an unread one also shows in Today's Needs you.
    public var asksForAction: Bool { NoticeKind.actionKinds.contains(kind) }
}

public enum NoticeKind: String, Sendable, Hashable, Codable, CaseIterable {
    case taskAssigned
    case taskActivity
    case approval
    case meeting
    case signature
    case survey
    case timeOff
    case other

    public static let actionKinds: Set<NoticeKind> = [.taskAssigned, .approval, .signature, .survey]
}

public struct NoticeFeed: Sendable, Hashable {
    public var items: [Notice]
    /// The server's own count, so it includes rows older than the first page.
    public var unreadCount: Int

    public init(items: [Notice] = [], unreadCount: Int = 0) {
        self.items = items
        self.unreadCount = unreadCount
    }

    func markingRead(_ ids: Set<String>) -> NoticeFeed {
        let newlyRead = items.filter { ids.contains($0.id) && !$0.isRead }.count
        var copy = self
        for index in copy.items.indices where ids.contains(copy.items[index].id) { copy.items[index].isRead = true }
        copy.unreadCount = max(0, unreadCount - newlyRead)
        return copy
    }
}
