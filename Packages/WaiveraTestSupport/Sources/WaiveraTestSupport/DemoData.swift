import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraFixtures

/// The demo world behind the fakes: the shared sprout_api fixtures plus a few extra payloads,
/// all run through the production mappers. "Today" is 1 November 2026 in America/Chicago,
/// the day DST ends, so one of today's events crosses the repeated hour.
public struct DemoData: Sendable {
    /// 09:00 CST on 1 November 2026.
    public static let now = Date(timeIntervalSince1970: 1_793_545_200)
    public static let timeZone =
        TimeZone(identifier: "America/Chicago") ?? TimeZone(secondsFromGMT: -6 * 3_600)
        ?? .current
    public static let today = CalendarDate(now, in: timeZone)
    public static let viewerId = "usr_alex_rivera"

    public var user: CurrentUser
    /// Inbox rows: an unread 1:1, an unread channel, an archived channel, an unread group and
    /// a bot with a ticket card.
    public var conversations: [Conversation]
    /// Root messages per conversation, oldest first.
    public var messages: [Int: [ChatMessage]]
    /// Threads by root message id.
    public var threads: [Int: ThreadTimeline]
    /// Unconfirmed sends; the demo has one failed send showing Retry.
    public var pending: [OutgoingMessage]
    public var activity: [ActivityItem]
    public var bookmarks: [Bookmark]
    public var directory: [DirectoryPerson]
    public var people: [String: PersonProfile]
    public var calendar: CalendarFeed
    public var milestones: [Milestone]
    public var profile: OwnProfile
    public var organization: Organization

    /// Only the signed-in user; every list is empty.
    public static var empty: DemoData {
        var data = make()
        data.conversations = []
        data.messages = [:]
        data.threads = [:]
        data.pending = []
        data.activity = []
        data.bookmarks = []
        data.directory = []
        data.calendar = CalendarFeed()
        data.milestones = []
        data.profile = OwnProfile(profile: data.profile.profile, organization: data.organization)
        return data
    }

    public static func make() -> DemoData {
        let chat = ChatMapper(viewerId: viewerId)
        let organization =
            Self.list(OrganizationResponse.self, single: "rest-users-organization").first
            .map(ProfileMapper.organization) ?? Organization(id: 12, name: nil)
        let details = Self.enveloped(UserWithRoleDto.self, "rest-auth-get-user-details")
        let user = CurrentUser(
            id: viewerId,
            firebaseUid: "demo-firebase-uid",
            email: details?.email,
            firstName: details?.firstName,
            lastName: details?.lastName,
            displayName: details?.displayName,
            avatarURL: details?.avatarURL,
            timeZoneIdentifier: timeZone.identifier,
            organization: organization,
            roles: details?.roles ?? []
        )
        let conversations =
            (Self.list(ConversationResponse.self, "rest-chat-get-all")
            + Self.decode([ConversationResponse].self, DemoPayloads.conversations)).compactMap(chat.conversation)
        let chatContent = Self.chatContent(chat, conversations: conversations)
        return DemoData(
            user: user,
            conversations: conversations,
            messages: chatContent.messages,
            threads: chatContent.threads,
            pending: [Self.failedSend],
            activity: Self.list(ChatActivityResponse.self, "rest-chat-recent-activity").compactMap(chat.activity),
            bookmarks: Self.list(MessageSendResponse.self, "rest-chat-get-bookmarks").compactMap { chat.message($0) }
                .map(Bookmark.init),
            directory: Self.directory,
            people: Self.people(details: details),
            calendar: Self.calendarFeed,
            milestones: (Self.list(CalendarEmployeeMilestoneResponseDto.self, "rest-calendar-get-milestones")
                + Self.decode([CalendarEmployeeMilestoneResponseDto].self, DemoPayloads.milestones))
                .compactMap(CalendarMapper.milestone),
            profile: Self.ownProfile(organization: organization),
            organization: organization
        )
    }

    // MARK: Chat

    private static let failedSend = OutgoingMessage(
        clientMessageId: "demo-failed-send",
        conversationId: 7,
        parentMessageId: nil,
        text: "Running 5 minutes late",
        doc: nil,
        createdAt: now.addingTimeInterval(-600),
        state: .failed(.offline),
        attempts: 3
    )

    private static let messageFixtures = [
        "rest-chat-get-messages-pagination-with-attachment", "rest-chat-get-messages-pagination-reply",
        "rest-chat-get-messages-pagination-with-reaction", "rest-chat-get-messages-pagination-richtext",
        "rest-chat-get-messages-pagination-system-message",
    ]

    private static func chatContent(
        _ chat: ChatMapper,
        conversations: [Conversation]
    ) -> (messages: [Int: [ChatMessage]], threads: [Int: ThreadTimeline]) {
        var all = messageFixtures.flatMap { list(MessageSendResponse.self, $0) }
        all += decode([MessageSendResponse].self, DemoPayloads.groupMessages)
        all += decode([MessageSendResponse].self, DemoPayloads.callLog)
        all += [decode(MessageSendResponse.self, DemoPayloads.ticketMessage)].compactMap { $0 }
        var byId: [Int: ChatMessage] = [:]
        for message in conversations.compactMap(\.lastMessage) + all.compactMap({ chat.message($0) }) {
            byId[message.id] = byId[message.id]?.merging(message) ?? message
        }
        let threadRows = list(MessageSendResponse.self, "rest-chat-get-thread").compactMap { chat.message($0) }
        var threads: [Int: ThreadTimeline] = [:]
        for reply in byId.values.filter(\.isThreadReply) + threadRows.filter(\.isThreadReply) {
            guard let rootId = reply.threadRootId,
                let root = byId[rootId] ?? threadRows.first(where: { $0.id == rootId })
            else { continue }
            var thread =
                threads[rootId]
                ?? ThreadTimeline(
                    rootMessageId: rootId,
                    conversationId: root.conversationId,
                    root: root
                )
            if !thread.replies.contains(where: { $0.id == reply.id }) { thread.replies.append(reply) }
            thread.replies.sort { ($0.createdAt ?? .distantPast, $0.id) < ($1.createdAt ?? .distantPast, $1.id) }
            threads[rootId] = thread
        }
        for (rootId, thread) in threads {
            if var root = byId[rootId] {
                root.threadReplyCount = max(root.threadReplyCount, thread.replies.count)
                byId[rootId] = root
            }
            threads[rootId]?.root = byId[rootId] ?? thread.root
        }
        let roots = byId.values.filter { !$0.isThreadReply }
        let messages = Dictionary(grouping: roots, by: \.conversationId).mapValues { rows in
            rows.sorted { ($0.createdAt ?? .distantPast, $0.id) < ($1.createdAt ?? .distantPast, $1.id) }
        }
        return (messages, threads)
    }

    // MARK: People, calendar and profile

    private static var directory: [DirectoryPerson] {
        let rows = list(GetUserNameResponseVM.self, "rest-auth-get-username-list")
            .map { DirectoryPerson(id: $0.userId, name: $0.userName ?? $0.userId) }
        return (rows + [DirectoryPerson(id: "usr_sam_ortiz", name: "Sam Ortiz")]).sorted { $0.name < $1.name }
    }

    private static func people(details: UserWithRoleDto?) -> [String: PersonProfile] {
        var people: [String: PersonProfile] = [:]
        for user in decode([UserInfoResponse].self, DemoPayloads.people) {
            guard let id = user.id else { continue }
            var person = PersonProfile(id: id, displayName: user.displayName)
            person.firstName = user.firstName
            person.lastName = user.lastName
            person.timeZoneIdentifier = timeZone.identifier
            people[id] = person
        }
        if let details { people[details.id] = ProfileMapper.person(details) }
        return people
    }

    private static var calendarFeed: CalendarFeed {
        var feed =
            enveloped(CalendarFeedResponseDto.self, "rest-calendar-get-all-event")
            ?? CalendarFeedResponseDto(events: [], timeOff: [], holidays: [])
        feed.events += decode([CalendarEventResponseDto].self, DemoPayloads.todaysEvents)
        return CalendarMapper(viewerId: viewerId).feed(feed)
    }

    private static func ownProfile(organization: Organization) -> OwnProfile {
        OwnProfile(
            profile: enveloped(GetEmployeeProfileDto.self, "rest-employee-get-profile").map(ProfileMapper.profile),
            timeOff: enveloped([TimeOffProfileItemDto].self, "rest-timeoff-get-for-user-profile")
                .map(ProfileMapper.timeOff),
            files: (enveloped(EmployeeFilesPage.self, "rest-employee-get-employee-files")?.items ?? [])
                .map(ProfileMapper.file),
            organization: organization
        )
    }

    // MARK: Decoding

    private struct Envelope<T: Decodable>: Decodable {
        var data: T?
    }

    private struct EmployeeFilesPage: Decodable {
        var items: [EmployeeFileDto]
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? WaiveraJSON.decoder().decode(type, from: Data(json.utf8))
    }

    static func decode<T: Decodable>(_ type: [T].Type, _ json: String) -> [T] {
        (try? WaiveraJSON.decoder().decode(type, from: Data(json.utf8))) ?? []
    }

    static func enveloped<T: Decodable>(_ type: T.Type, _ fixture: String) -> T? {
        guard let data = try? Fixture.data(fixture) else { return nil }
        return (try? WaiveraJSON.decoder().decode(Envelope<T>.self, from: data))?.data
    }

    /// A fixture that is a bare array, an enveloped array, or (with `single`) one object.
    static func list<T: Decodable>(_ type: T.Type, _ fixture: String = "", single: String? = nil) -> [T] {
        if let single {
            guard let data = try? Fixture.data(single) else { return [] }
            return [try? WaiveraJSON.decoder().decode(T.self, from: data)].compactMap { $0 }
        }
        guard let data = try? Fixture.data(fixture) else { return [] }
        if let rows = try? WaiveraJSON.decoder().decode([T].self, from: data) { return rows }
        return enveloped([T].self, fixture) ?? []
    }
}
