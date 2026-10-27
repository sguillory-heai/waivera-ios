import Foundation
import WaiveraAPI
import WaiveraData

@testable import TodayFeature

/// Builders for Today's inputs. Every time is a UTC instant, written out so a reader can
/// check the local wall-clock time in America/Chicago by hand.
enum Fixture {
    static let chicago = TimeZone(identifier: "America/Chicago") ?? .current
    /// 10:30 CST on 1 November 2026, the day DST ends.
    static let now = instant("2026-11-01T16:30:00Z")
    static let today = CalendarDate(now, in: chicago)
    static let viewerId = "usr_viewer"

    static func instant(_ raw: String) -> Date {
        WaiveraInstant.parse(raw) ?? .distantPast
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        CalendarDate(year: year, month: month, day: day) ?? today
    }

    static func context(
        now: Date = now,
        connection: ConnectionBanner = .hidden,
        local: TodayLocalState = TodayLocalState(),
        activity: ActivityLocalState = ActivityLocalState()
    ) -> TodayContext {
        TodayContext(zone: chicago, now: now, connection: connection, local: local, activity: activity)
    }

    static func loaded<Value>(_ value: Value, at updatedAt: Date = now) -> Resource<Value> {
        Resource(value: value, phase: .loaded, updatedAt: updatedAt)
    }

    // MARK: Activity

    static func activity(
        _ id: Int64,
        _ kind: ActivityItem.Kind = .threadReply,
        at raw: String? = "2026-11-01T16:00:00Z",
        isRead: Bool = false,
        conversation: Int = 40,
        message: Int? = nil,
        threadRoot: Int? = nil,
        summary: String? = "Sam Ortiz replied in a thread.",
        actor: String? = "Sam Ortiz",
        emoji: String? = nil
    ) -> ActivityItem {
        var item = ActivityItem(
            id: id,
            kind: kind,
            conversationId: conversation,
            messageId: message ?? Int(id) + 1_000,
            isRead: isRead
        )
        item.createdAt = raw.map(instant)
        item.threadRootMessageId = threadRoot
        item.summary = summary
        item.actorDisplayName = actor
        item.reactionType = emoji
        return item
    }

    static func feed(_ items: [ActivityItem], hasMore: Bool = false) -> ActivityFeed {
        ActivityFeed(items: items, hasMore: hasMore)
    }

    // MARK: Conversations

    static func direct(
        _ id: Int,
        name: String = "Priya Raman",
        unread: Int = 1,
        text: String? = "Can you cover Thursday?",
        at raw: String = "2026-11-01T16:20:00Z",
        archived: Bool = false
    ) -> Conversation {
        let parts = name.split(separator: " ").map(String.init)
        var conversation = Conversation(
            id: id,
            kind: .direct,
            viewerId: viewerId,
            participants: [
                ChatUser(id: viewerId, firstName: "Alex", lastName: "Rivera"),
                ChatUser(id: "usr_\(id)", firstName: parts.first, lastName: parts.dropFirst().first),
            ]
        )
        var message = ChatMessage(id: id * 100, conversationId: id, createdAt: instant(raw))
        message.plaintext = text
        conversation.lastMessage = message
        conversation.unreadCount = unread
        conversation.isArchived = archived
        return conversation
    }

    static func channel(_ id: Int, unread: Int = 3) -> Conversation {
        var conversation = Conversation(id: id, kind: .channel, viewerId: viewerId)
        conversation.channel = ChannelInfo(name: "care-team")
        conversation.unreadCount = unread
        return conversation
    }

    static func bot(_ id: Int, unread: Int = 1, ticketId: String? = "4821", at raw: String = "2026-11-01T15:00:00Z")
        -> Conversation
    {
        var conversation = Conversation(id: id, kind: .bot, viewerId: viewerId)
        var message = ChatMessage(id: id * 100, conversationId: id, createdAt: instant(raw))
        message.isBot = true
        message.authorId = "bot:waivera"
        if let ticketId {
            message.systemEventType = TicketNotification.eventType
            message.systemEventData = .object([
                "ticketId": .string(ticketId),
                "title": .string("Wheelchair ramp repair"),
                "url": .string("https://tickets.invalid/4821"),
            ])
        } else {
            message.plaintext = "Status changed"
        }
        conversation.lastMessage = message
        conversation.unreadCount = unread
        return conversation
    }

    // MARK: Calendar

    static func event(
        _ id: String,
        _ start: String,
        _ end: String,
        title: String? = nil,
        response: InvitationState = .accepted,
        isOwner: Bool = false
    ) -> CalendarEvent {
        var event = CalendarEvent(id: id, title: title ?? id, start: instant(start), end: instant(end))
        event.viewerResponse = response
        event.isOwner = isOwner
        return event
    }

    static func allDay(_ id: String, from start: CalendarDate, until endExclusive: CalendarDate) -> CalendarEvent {
        var event = CalendarEvent(
            id: id,
            title: id,
            start: start.interval(in: chicago).start,
            end: endExclusive.interval(in: chicago).start
        )
        event.allDay = CalendarEvent.AllDaySpan(start: start, endExclusive: endExclusive)
        event.viewerResponse = .accepted
        return event
    }

    static func weeks(_ events: [CalendarEvent], at updatedAt: Date = now) -> [Resource<CalendarFeed>] {
        [loaded(CalendarFeed(events: events), at: updatedAt), loaded(CalendarFeed(), at: updatedAt)]
    }

    static func sources(
        conversations: [Conversation] = [],
        activity: [ActivityItem] = [],
        hasMore: Bool = false,
        events: [CalendarEvent] = [],
        milestones: [Milestone] = [],
        at updatedAt: Date = now
    ) -> TodaySources {
        TodaySources(
            conversations: loaded(conversations, at: updatedAt),
            activity: loaded(feed(activity, hasMore: hasMore), at: updatedAt),
            schedule: weeks(events, at: updatedAt),
            milestones: loaded(MilestoneIndex(milestones), at: updatedAt)
        )
    }
}
