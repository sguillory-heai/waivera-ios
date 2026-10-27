import Foundation
import WaiveraAPI
import WaiveraRealtime

/// Every repository the app and feature modules use, behind protocols. The app target builds
/// one with `DataEnvironment.live(...)`, or `FakeDataEnvironment.make()` from
/// WaiveraTestSupport under the DEBUG-only `-WaiveraFakeServer` launch argument.
public struct DataEnvironment: Sendable {
    public let session: any SessionRepository
    public let conversations: any ConversationsRepository
    public let messages: any MessagesRepository
    public let threads: any ThreadsRepository
    public let attachments: any AttachmentsRepository
    public let avatars: any AvatarRepository
    public let bookmarks: any BookmarksRepository
    public let activity: any ActivityRepository
    public let people: any PeopleRepository
    public let calendar: any CalendarRepository
    public let profile: any ProfileRepository
    public let settings: any SettingsRepository
    public let push: any PushRegistrationRepository
    public let realtimeStatus: any RealtimeStatusRepository
    public let alerts: any ChatAlertsRepository
    /// Opens a conversation's call in the web lobby (03 §19).
    public let callURL: @Sendable (Conversation) async throws -> URL
    private let foreground: @Sendable (Bool) async -> Void
    private let start: @Sendable () async -> Void

    public init(
        session: any SessionRepository,
        conversations: any ConversationsRepository,
        messages: any MessagesRepository,
        threads: any ThreadsRepository,
        attachments: any AttachmentsRepository,
        avatars: any AvatarRepository,
        bookmarks: any BookmarksRepository,
        activity: any ActivityRepository,
        people: any PeopleRepository,
        calendar: any CalendarRepository,
        profile: any ProfileRepository,
        settings: any SettingsRepository,
        push: any PushRegistrationRepository,
        realtimeStatus: any RealtimeStatusRepository,
        alerts: any ChatAlertsRepository,
        callURL: @escaping @Sendable (Conversation) async throws -> URL,
        foreground: @escaping @Sendable (Bool) async -> Void,
        start: @escaping @Sendable () async -> Void
    ) {
        self.session = session
        self.conversations = conversations
        self.messages = messages
        self.threads = threads
        self.attachments = attachments
        self.avatars = avatars
        self.bookmarks = bookmarks
        self.activity = activity
        self.people = people
        self.calendar = calendar
        self.profile = profile
        self.settings = settings
        self.push = push
        self.realtimeStatus = realtimeStatus
        self.alerts = alerts
        self.callURL = callURL
        self.foreground = foreground
        self.start = start
    }

    /// Call once at launch: reads the stored session and bootstraps.
    public func launch() async { await start() }

    /// Scene phase: realtime is foreground-only (05 §2).
    public func setForeground(_ isForeground: Bool) async { await foreground(isForeground) }
}
