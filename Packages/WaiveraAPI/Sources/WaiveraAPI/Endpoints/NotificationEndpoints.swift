import Foundation

/// `Controllers/NotificationController.cs` (`api/notifications`): the stored notifications the
/// web bell shows. The list is a bare array, newest first; the count and writes are enveloped.
extension APIClient {
    public static let notificationPageSize = 30

    public func notifications(page: Int = 1, pageSize: Int = APIClient.notificationPageSize) async throws
        -> [EventNotificationResponse]
    {
        let request = APIRequest(
            .get,
            "api/notifications",
            query: [
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
            ]
        )
        return try await decode(request, as: LossyArray<EventNotificationResponse>.self).elements
    }

    public func notificationUnreadCount() async throws -> Int {
        try await enveloped(APIRequest(.get, "api/notifications/unread-count"), as: Int.self)
    }

    public func markNotificationRead(id: String) async throws {
        _ = try await send(APIRequest(.put, "api/notifications/\(escape(id))"))
    }

    public func markAllNotificationsRead() async throws {
        _ = try await send(APIRequest(.put, "api/notifications/mark-all-read"))
    }
}
