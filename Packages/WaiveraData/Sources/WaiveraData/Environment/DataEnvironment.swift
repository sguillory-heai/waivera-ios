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
    /// The web bell's notifications (the Today inbox).
    public let notices: any NoticesRepository
    /// Casework and the person's own tasks, straight from the server.
    public let tasks: any TasksRepository
    /// Change requests on tasks and their review.
    public let requests: any RequestsRepository
    /// The clock the repositories stamp `updatedAt` with. Relative times on screen ("5m",
    /// "Updated 2 min ago") measure against it, so the fake environment's demo day stays consistent.
    public let clock: any WaiveraClock
    /// The web app's address, for pages the phone has no screen for; only its own host is opened.
    public let webBaseURL: URL?
    /// Opens a conversation's call in the web lobby (03 §19).
    public let callURL: @Sendable (Conversation) async throws -> URL
    private let foreground: @Sendable (Bool) async -> Void
    private let start: @Sendable () async -> Void
    private let protectedData: @Sendable () async -> Void

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
        notices: any NoticesRepository = EmptyNoticesRepository(),
        tasks: any TasksRepository = EmptyTasksRepository(),
        requests: any RequestsRepository = EmptyRequestsRepository(),
        clock: any WaiveraClock = SystemClock(),
        webBaseURL: URL? = nil,
        callURL: @escaping @Sendable (Conversation) async throws -> URL,
        foreground: @escaping @Sendable (Bool) async -> Void,
        start: @escaping @Sendable () async -> Void,
        protectedDataAvailable: @escaping @Sendable () async -> Void = {}
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
        self.notices = notices
        self.tasks = tasks
        self.requests = requests
        self.clock = clock
        self.webBaseURL = webBaseURL
        self.callURL = callURL
        self.foreground = foreground
        self.start = start
        protectedData = protectedDataAvailable
    }

    /// Call once at launch: reads the stored session and bootstraps.
    public func launch() async { await start() }

    /// Scene phase: realtime is foreground-only (05 §2).
    public func setForeground(_ isForeground: Bool) async { await foreground(isForeground) }

    /// The device was unlocked: a session the locked Keychain hid at launch can load now (IS-03).
    public func protectedDataDidBecomeAvailable() async { await protectedData() }
}
