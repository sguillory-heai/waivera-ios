import Foundation
import WaiveraAPI
import WaiveraRealtime

// The interfaces feature modules code against. Every stream replays its current value on
// subscription. Live implementations are in this package; fakes are in WaiveraTestSupport.

/// Sign-in, the session gate and sign-out (01).
public protocol SessionRepository: Sendable {
    func states() -> AsyncStream<SessionState>
    var currentState: SessionState { get }
    /// Reads the stored Firebase session and bootstraps once per identity.
    func start() async
    func signIn(email: String, password: String) async throws
    /// Firebase's reset email. An unknown address throws `.auth(.invalidCredentials)`; screens
    /// show the same "sent" copy for it so they never reveal whether an account exists.
    func sendPasswordReset(email: String) async throws
    /// Firebase password update, then the backend confirmation. From the forced gate it re-runs
    /// the bootstrap; signed in (Settings) the session stays `.signedIn` throughout. If Firebase
    /// took the new password but the confirmation failed, a retry with the same new password
    /// only repeats the confirmation.
    func changePassword(current: String, new: String) async throws
    /// Retries the backend login after a failure without signing out.
    func retryBootstrap() async
    /// The single sign-out path: unregister push, stop realtime, clear caches, then Firebase.
    func signOut() async
}

/// The inbox (02).
public protocol ConversationsRepository: Sendable {
    func conversations() -> AsyncStream<Resource<[Conversation]>>
    func refresh() async
    /// The cached row, else the detail endpoint.
    func conversation(id: Int) async throws -> Conversation
    /// Typing users per conversation, already excluding the viewer and expired entries.
    func typing() -> AsyncStream<[Int: [String]]>
    func totalUnread() -> AsyncStream<Int>
    /// Get-or-create the 1:1 conversation with `userId`.
    func openDirectConversation(with userId: String) async throws -> Conversation
    func createConversation(participantIds: [String]) async throws -> Conversation
    func leave(conversationId: Int) async throws
}

/// Actions on any message, from the conversation or a thread.
public protocol MessageActions: Sendable {
    /// Re-sends a failed message with the same client id.
    func retry(clientMessageId: String) async
    /// Drops a failed message ("delete draft").
    func discard(clientMessageId: String) async
    func edit(messageId: Int, conversationId: Int, text: String) async throws
    func delete(messageId: Int, conversationId: Int) async throws
    /// Optimistic; rolls back and throws when the hub call fails. Hub-only (gap G-01).
    func toggleReaction(_ emoji: String, messageId: Int, conversationId: Int) async throws
}

/// One conversation's timeline (03).
public protocol MessagesRepository: MessageActions {
    func timeline(conversationId: Int) -> AsyncStream<Resource<MessageTimeline>>
    /// The screen appeared: join the hub group, mark it visible, load or resync.
    func open(conversationId: Int) async
    func close(conversationId: Int) async
    func refresh(conversationId: Int) async
    func loadOlder(conversationId: Int) async
    /// Brings `messageId` into the loaded timeline through the message-context endpoint, with
    /// no gap between it and the newest message (03 §9). Returns whether it is there now.
    @discardableResult
    func loadAround(conversationId: Int, messageId: Int) async throws -> Bool
    /// Enqueues an optimistic send; `nil` when there is nothing to send.
    @discardableResult
    func send(text: String, attachment: Attachment?, conversationId: Int) async -> OutgoingMessage?
    /// Notification replies (IF-03): queues the message (in its thread when
    /// `threadRootMessageId` is set), returns only after the queue is on disk, then waits up to
    /// `timeout` for the first send. Whatever the outcome, a queued message survives relaunch.
    func sendAndWait(text: String, conversationId: Int, threadRootMessageId: Int?, timeout: Duration) async
        -> OutboxOutcome
    /// Mark-as-read plus read-through of the newest root message (03 §12). Optimistic: the
    /// unread count clears at once and is restored, with the error thrown, when the server call
    /// fails, so the screen can offer Retry.
    func markRead(conversationId: Int) async throws
    /// Composer text changed; throttles typing to one event per 3 s.
    func composerChanged(conversationId: Int, text: String) async
}

/// One thread (04).
public protocol ThreadsRepository: MessageActions {
    func thread(rootMessageId: Int, conversationId: Int) -> AsyncStream<Resource<ThreadTimeline>>
    func open(rootMessageId: Int, conversationId: Int) async
    func close(rootMessageId: Int, conversationId: Int) async
    func refresh(rootMessageId: Int, conversationId: Int) async
    @discardableResult
    func reply(text: String, attachment: Attachment?, rootMessageId: Int, conversationId: Int) async
        -> OutgoingMessage?
    func markRead(rootMessageId: Int, conversationId: Int) async
}

/// Uploads and authenticated downloads (03 §8, gap G-15).
public protocol AttachmentsRepository: Sendable {
    func upload(data: Data, fileName: String, mimeType: String) async throws -> Attachment
    /// Cached after the first download; throws `.attachmentBlocked` on 423.
    func data(forMessageId messageId: Int) async throws -> Data
}

/// Avatar images with a memory cache and a negative cache for users without one.
public protocol AvatarRepository: Sendable {
    func avatar(userId: String) async -> Data?
}

/// Saved messages (06 §B, gap G-04).
public protocol BookmarksRepository: Sendable {
    func bookmarks() -> AsyncStream<Resource<BookmarkList>>
    func refresh() async
    /// Returns the new state.
    @discardableResult
    func toggle(messageId: Int, conversationId: Int) async throws -> Bool
}

/// Mentions, replies and reactions (06 §A).
public protocol ActivityRepository: Sendable {
    func feed() -> AsyncStream<Resource<ActivityFeed>>
    func refresh() async
    func loadMore() async
    /// Optimistic; restores and throws on failure so the screen can show a toast.
    func markRead(activityId: Int64) async throws
    func markAllRead() async throws
}

/// The staff directory and person detail (06 §C).
public protocol PeopleRepository: Sendable {
    func directory() -> AsyncStream<Resource<[DirectoryPerson]>>
    func refresh() async
    func person(id: String) async throws -> PersonProfile
}

/// Calendar, milestones and invitations (07). Every date is in the employee's saved zone.
public protocol CalendarRepository: Sendable {
    /// The zone schedules render in, and whether it fell back to America/Chicago (dates.md §2).
    func scheduleTimeZone() -> (zone: TimeZone, isFallback: Bool)
    /// Today's date in the schedule zone.
    func today() -> CalendarDate
    func feed(period: CalendarPeriod, containing date: CalendarDate) -> AsyncStream<Resource<CalendarFeed>>
    func refresh(period: CalendarPeriod, containing date: CalendarDate) async
    func respond(toEventId eventId: String, accept: Bool) async throws
    /// One event by id (a push, a deep link, Today). Replays the copy from any loaded feed at
    /// once; `refreshEvent` asks the server. `.notFound` when the server has no such event for
    /// this person (deleted, or another organization).
    func event(id: String) -> AsyncStream<Resource<EventLookup>>
    func refreshEvent(id: String) async
    func milestones() -> AsyncStream<Resource<MilestoneIndex>>
    func refreshMilestones() async
    /// The web lobby URL for a Waivera ("Sprout") meeting (07 §7).
    func meetingURL(for event: CalendarEvent) async throws -> URL
}

/// The own profile screen (08 §1-5).
public struct OwnProfile: Sendable, Hashable {
    /// Time off and files load and fail on their own (08 §2-4); the screen fails only when
    /// the main record does.
    public struct SectionPhases: Sendable, Hashable {
        public var timeOff: ResourcePhase
        public var files: ResourcePhase

        public init(timeOff: ResourcePhase = .idle, files: ResourcePhase = .idle) {
            self.timeOff = timeOff
            self.files = files
        }
    }

    public var profile: EmployeeProfile?
    public var timeOff: TimeOffOverview?
    /// At most five, newest first.
    public var files: [EmployeeFile]
    /// Matched to the session's organization by id only (08 §5).
    public var organization: Organization?
    public var sections: SectionPhases

    public init(
        profile: EmployeeProfile? = nil,
        timeOff: TimeOffOverview? = nil,
        files: [EmployeeFile] = [],
        organization: Organization? = nil,
        sections: SectionPhases = SectionPhases(timeOff: .loaded, files: .loaded)
    ) {
        self.profile = profile
        self.timeOff = timeOff
        self.files = files
        self.organization = organization
        self.sections = sections
    }
}

/// A profile card that reloads on its own (its Retry).
public enum ProfileSection: Sendable, Hashable {
    case timeOff, files
}

public protocol ProfileRepository: Sendable {
    func profile() -> AsyncStream<Resource<OwnProfile>>
    func refresh() async
    /// Reloads one card without touching the others.
    func refresh(section: ProfileSection) async
}

/// Device-stored settings (08 §7-8).
public protocol SettingsRepository: Sendable {
    func settings() -> AsyncStream<AppSettings>
    var currentSettings: AppSettings { get }
    func update(_ transform: @Sendable (inout AppSettings) -> Void) async
}

/// FCM token registration with sprout_api (09 §5, gap G-08).
public protocol PushRegistrationRepository: Sendable {
    /// Registers, or re-registers when the token or preferences changed. Retries with backoff.
    func register(token: String, preferences: NotificationPreferences) async
    /// Unregisters this install (sign-out, or push switched off).
    func unregister() async
}

/// The quiet connection banner (05 §2).
public enum ConnectionBanner: Sendable, Hashable {
    case hidden
    case connecting
    case reconnecting(attempt: Int)
    /// The device is offline; realtime waits for the network.
    case offline
}

public protocol RealtimeStatusRepository: Sendable {
    func banner() -> AsyncStream<ConnectionBanner>
    func statuses() -> AsyncStream<RealtimeStatus>
    /// The banner's Retry action.
    func retryNow() async
}

/// An in-app alert for a message outside the visible conversation (05 §9, gap G-09).
public struct ChatAlert: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        case mention, threadReply, message
    }

    public var conversationId: Int
    public var messageId: Int
    public var reason: Reason
    public var title: ConversationTitle?
    /// `nil` when previews are switched off; the screen shows generic copy.
    public var preview: String?
    public var destination: ChatDestination

    public init(
        conversationId: Int,
        messageId: Int,
        reason: Reason,
        title: ConversationTitle?,
        preview: String?,
        destination: ChatDestination
    ) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.reason = reason
        self.title = title
        self.preview = preview
        self.destination = destination
    }
}

public protocol ChatAlertsRepository: Sendable {
    func alerts() -> AsyncStream<ChatAlert>
    /// Foreground push suppression: only when the hub is connected and the message's surface
    /// is on screen, the timeline for a root message and the thread for a reply (PLAN parity
    /// fix, 09 §2, IF-02).
    func shouldPresentForegroundPush(conversationId: Int?, threadRootMessageId: Int?) -> Bool
    /// Conversations read anywhere: opened on screen, marked read, or read on another device.
    /// The app clears their delivered notifications (09 §6, IF-07).
    func conversationsRead() -> AsyncStream<Int>
}

extension ChatAlertsRepository {
    /// A root message (or a push without a thread root).
    public func shouldPresentForegroundPush(conversationId: Int?) -> Bool {
        shouldPresentForegroundPush(conversationId: conversationId, threadRootMessageId: nil)
    }

    public func conversationsRead() -> AsyncStream<Int> { AsyncStream { $0.finish() } }
}
