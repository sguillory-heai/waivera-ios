import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraRealtime

/// Sign-in accepts `FakeSessionRepository.password` for any email and runs the same gates as
/// the live session.
public final class FakeSessionRepository: SessionRepository {
    public static let password = "waivera-demo"

    private let cell: StateCell<SessionState>
    private let user: CurrentUser
    public let calls = CallLog()
    /// What the next backend bootstrap returns; `nil` signs in.
    public let bootstrapFailure = LockedValue<WaiveraError?>(nil)
    public let requiresPasswordChange = LockedValue(false)
    private let onSignOut: @Sendable () async -> Void

    public init(
        user: CurrentUser,
        initial: SessionState = .loading,
        onSignOut: @escaping @Sendable () async -> Void = {}
    ) {
        self.user = user
        cell = StateCell(initial)
        self.onSignOut = onSignOut
    }

    public func states() -> AsyncStream<SessionState> { cell.stream() }
    public var currentState: SessionState { cell.current }

    public func start() async {
        calls.record("start")
        if cell.current == .loading { bootstrap() }
    }

    public func signIn(email: String, password: String) async throws {
        calls.record("signIn")
        guard password == Self.password else { throw WaiveraError.auth(.invalidCredentials) }
        bootstrap()
    }

    public func changePassword(current: String, new: String) async throws {
        calls.record("changePassword")
        guard current == Self.password else { throw WaiveraError.auth(.invalidCredentials) }
        requiresPasswordChange.update { $0 = false }
        bootstrap()
    }

    public func retryBootstrap() async {
        calls.record("retryBootstrap")
        bootstrap()
    }

    public func signOut() async {
        calls.record("signOut")
        await onSignOut()
        cell.set(.signedOut(nil))
    }

    private func bootstrap() {
        if let failure = bootstrapFailure.get() {
            cell.set(failure == .unauthorized ? .signedOut(.unauthorized) : .bootstrapFailed(failure))
        } else if requiresPasswordChange.get() {
            cell.set(.passwordChangeRequired(user))
        } else {
            cell.set(.signedIn(user))
        }
    }
}

public final class FakeAttachmentsRepository: AttachmentsRepository {
    public let calls = CallLog()
    public let uploadFailure = LockedValue<WaiveraError?>(nil)
    /// Message ids whose download is quarantined (423).
    public let blockedMessageIds = LockedValue<Set<Int>>([])

    public init() {}

    public func upload(data: Data, fileName: String, mimeType: String) async throws -> Attachment {
        calls.record("upload:\(fileName)")
        if let failure = uploadFailure.get() { throw failure }
        return Attachment(
            url: "chat/demo/\(fileName)",
            kind: Attachment.kind(contentType: mimeType, type: nil, name: fileName),
            name: fileName,
            contentType: mimeType,
            size: Int64(data.count),
            scanStatus: .clean
        )
    }

    public func data(forMessageId messageId: Int) async throws -> Data {
        calls.record("download:\(messageId)")
        if blockedMessageIds.get().contains(messageId) { throw WaiveraError.attachmentBlocked }
        return Data("demo attachment \(messageId)".utf8)
    }
}

/// No avatars: screens show initials, which keeps snapshots stable.
public final class FakeAvatarRepository: AvatarRepository {
    public init() {}
    public func avatar(userId: String) async -> Data? { nil }
}

public final class FakeBookmarksRepository: BookmarksRepository {
    public let resource: FakeResource<BookmarkList>
    public let calls = CallLog()

    public init(_ bookmarks: [Bookmark], clock: any WaiveraClock) {
        resource = FakeResource(BookmarkList(bookmarks: bookmarks), clock: clock)
    }

    public func bookmarks() -> AsyncStream<Resource<BookmarkList>> { resource.stream() }
    public func refresh() async { await resource.refresh() }

    @discardableResult
    public func toggle(messageId: Int, conversationId: Int) async throws -> Bool {
        calls.record("toggle:\(messageId)")
        let isBookmarked = !(resource.value?.bookmarks.contains { $0.id == messageId } ?? false)
        resource.mutate { list in
            if isBookmarked {
                var message = ChatMessage(id: messageId, conversationId: conversationId)
                message.isBookmarked = true
                list.bookmarks.insert(Bookmark(message: message), at: 0)
            } else {
                list.bookmarks.removeAll { $0.id == messageId }
            }
        }
        return isBookmarked
    }
}

public final class FakeActivityRepository: ActivityRepository {
    public let resource: FakeResource<ActivityFeed>
    public let calls = CallLog()
    public let actionFailure = LockedValue<WaiveraError?>(nil)

    public init(_ items: [ActivityItem], clock: any WaiveraClock) {
        resource = FakeResource(ActivityFeed(items: items), clock: clock)
    }

    public func feed() -> AsyncStream<Resource<ActivityFeed>> { resource.stream() }
    public func refresh() async { await resource.refresh() }
    public func loadMore() async { calls.record("loadMore") }

    public func markRead(activityId: Int64) async throws {
        calls.record("markRead:\(activityId)")
        if let failure = actionFailure.get() { throw failure }
        resource.mutate { feed in
            for index in feed.items.indices where feed.items[index].id == activityId { feed.items[index].isRead = true }
        }
    }

    public func markAllRead() async throws {
        calls.record("markAllRead")
        if let failure = actionFailure.get() { throw failure }
        resource.mutate { feed in
            for index in feed.items.indices { feed.items[index].isRead = true }
        }
    }
}

public final class FakePeopleRepository: PeopleRepository {
    public let resource: FakeResource<[DirectoryPerson]>
    private let people: [String: PersonProfile]

    public init(directory: [DirectoryPerson], people: [String: PersonProfile], clock: any WaiveraClock) {
        resource = FakeResource(directory, clock: clock)
        self.people = people
    }

    public func directory() -> AsyncStream<Resource<[DirectoryPerson]>> { resource.stream() }
    public func refresh() async { await resource.refresh() }

    public func person(id: String) async throws -> PersonProfile {
        if let failure = resource.current.error { throw failure }
        guard let person = people[id] else { throw WaiveraError.notFound }
        return person
    }
}

public final class FakeProfileRepository: ProfileRepository {
    public let resource: FakeResource<OwnProfile>

    public init(_ profile: OwnProfile, clock: any WaiveraClock) {
        resource = FakeResource(profile, clock: clock)
    }

    public func profile() -> AsyncStream<Resource<OwnProfile>> { resource.stream() }
    public func refresh() async { await resource.refresh() }
}

public final class FakeSettingsRepository: SettingsRepository {
    private let cell: StateCell<AppSettings>

    public init(_ settings: AppSettings = AppSettings()) {
        cell = StateCell(settings)
    }

    public func settings() -> AsyncStream<AppSettings> { cell.stream() }
    public var currentSettings: AppSettings { cell.current }
    public func update(_ transform: @Sendable (inout AppSettings) -> Void) async { cell.update(transform) }
}

/// Records registrations; nothing leaves the device.
public final class FakePushRegistrationRepository: PushRegistrationRepository {
    public struct Registration: Sendable, Hashable {
        public var token: String
        public var preferences: NotificationPreferences
    }

    public let registrations = LockedValue<[Registration]>([])
    public let unregisterCount = LockedValue(0)

    public init() {}

    public func register(token: String, preferences: NotificationPreferences) async {
        registrations.update { $0.append(Registration(token: token, preferences: preferences)) }
    }

    public func unregister() async { unregisterCount.update { $0 += 1 } }
}

public final class FakeRealtimeStatusRepository: RealtimeStatusRepository {
    private let realtime: FakeRealtimeClient
    private let cell = StateCell(ConnectionBanner.hidden)
    private let task = LockedValue<Task<Void, Never>?>(nil)

    public init(realtime: FakeRealtimeClient) {
        self.realtime = realtime
        let statuses = realtime.statuses()
        let cell = cell
        task.update {
            $0 = Task {
                for await status in statuses {
                    let banner = Self.banner(status)
                    if cell.current != banner { cell.set(banner) }
                }
            }
        }
    }

    deinit { task.get()?.cancel() }

    static func banner(_ status: RealtimeStatus) -> ConnectionBanner {
        switch status.state {
        case .connected, .disconnected: .hidden
        case .connecting: status.epoch == 0 ? .connecting : .reconnecting(attempt: 1)
        case .reconnecting(let attempt, _): .reconnecting(attempt: attempt)
        }
    }

    /// Shows the offline banner regardless of the hub (airplane mode in UI tests).
    public func setOffline(_ offline: Bool) {
        cell.set(offline ? .offline : Self.banner(realtime.currentStatus))
    }

    public func banner() -> AsyncStream<ConnectionBanner> { cell.stream() }
    public func statuses() -> AsyncStream<RealtimeStatus> { realtime.statuses() }
    public func retryNow() async { await realtime.retryNow() }
}

public final class FakeChatAlertsRepository: ChatAlertsRepository {
    private let broadcaster = AsyncBroadcaster<ChatAlert>(replays: false)
    /// Conversations the fake treats as on screen with a live hub.
    public let activeConversationIds = LockedValue<Set<Int>>([])

    public init() {}

    public func alerts() -> AsyncStream<ChatAlert> { broadcaster.stream() }

    public func shouldPresentForegroundPush(conversationId: Int?) -> Bool {
        guard let conversationId else { return true }
        return !activeConversationIds.get().contains(conversationId)
    }

    /// Shows an in-app banner, as `ReceiveChatAttention` would.
    public func emit(_ alert: ChatAlert) { broadcaster.send(alert) }
}
