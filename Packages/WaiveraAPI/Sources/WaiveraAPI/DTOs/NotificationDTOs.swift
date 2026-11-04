import Foundation

/// Mirrors `EventNotificationResponse` (`GET api/notifications`): one row of the web bell. The
/// id is a GUID or a prefixed key such as `esign-request-…`; older rows send a number.
public struct EventNotificationResponse: Decodable, Sendable, Hashable {
    public var id: String
    public var type: String?
    public var status: String?
    public var title: String?
    public var message: String?
    public var actionUrl: String?
    public var createdAt: Date?
    public var read: Bool
    /// The creator's display name, first or last name, from `createdByUser` (any shape).
    public var createdByName: String?
    public var notificationResources: [NotificationResourceDto]

    public init(
        id: String,
        type: String? = nil,
        status: String? = nil,
        title: String? = nil,
        message: String? = nil,
        actionUrl: String? = nil,
        createdAt: Date? = nil,
        read: Bool = false,
        createdByName: String? = nil,
        notificationResources: [NotificationResourceDto] = []
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.title = title
        self.message = message
        self.actionUrl = actionUrl
        self.createdAt = createdAt
        self.read = read
        self.createdByName = createdByName
        self.notificationResources = notificationResources
    }

    enum CodingKeys: String, CodingKey {
        case id, type, status, title, message, actionUrl, createdAt, read, createdByUser, notificationResources
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(LenientID.self, forKey: .id)?.value ?? ""
        type = container.lenient(String.self, forKey: .type)
        status = container.lenient(String.self, forKey: .status)
        title = container.lenient(String.self, forKey: .title)
        message = container.lenient(String.self, forKey: .message)
        actionUrl = container.lenient(String.self, forKey: .actionUrl)
        createdAt = container.lenient(Date.self, forKey: .createdAt)
        read = container.lenientBool(forKey: .read)
        notificationResources = container.lenientArray(NotificationResourceDto.self, forKey: .notificationResources)
        createdByName = Self.name(container.lenient(JSONValue.self, forKey: .createdByUser))
    }

    /// The server fills `createdByUser` from the resources' creator when no `user` resource names them.
    private static func name(_ user: JSONValue?) -> String? {
        func field(_ key: String) -> String? {
            let value = user?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        if let display = field("displayName") { return display }
        let joined = [field("firstName"), field("lastName")].compactMap(\.self).joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}

/// `Models/NotificationResource.cs`: what a notification points at (task, file, meeting, …).
public struct NotificationResourceDto: Decodable, Sendable, Hashable {
    public var resourceId: String
    public var resourceType: String
    public var resourceName: String?

    public init(resourceId: String, resourceType: String, resourceName: String? = nil) {
        self.resourceId = resourceId
        self.resourceType = resourceType
        self.resourceName = resourceName
    }

    enum CodingKeys: String, CodingKey { case resourceId, resourceType, resourceName }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resourceId = container.lenient(LenientID.self, forKey: .resourceId)?.value ?? ""
        resourceType = container.lenient(String.self, forKey: .resourceType) ?? ""
        resourceName = container.lenient(String.self, forKey: .resourceName)
    }
}

/// Hub `ReceiveNotificationRead`: a stored notification, or with `all` every one, was read on
/// another device (`NotificationService.SyncNotificationReadAsync`).
public struct NotificationReadDto: Decodable, Sendable, Hashable {
    public var notificationId: String?
    public var all: Bool

    public init(notificationId: String?, all: Bool) {
        self.notificationId = notificationId
        self.all = all
    }

    enum CodingKeys: String, CodingKey { case notificationId, all }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = container.lenient(LenientID.self, forKey: .notificationId)?.value
        notificationId = id?.isEmpty == false ? id : nil
        all = container.lenientBool(forKey: .all)
    }
}
