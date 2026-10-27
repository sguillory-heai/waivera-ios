import Foundation
import WaiveraAPI
import WaiveraData

/// A wall-clock time in the employee's saved zone. Kept apart from `Date` so a label always
/// says what the clock on the wall says there, whatever zone the device is in.
struct ClockTime: Hashable, Sendable, Comparable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(_ date: Date, in zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? 0
        minute = parts.minute ?? 0
    }

    static let midnight = ClockTime(hour: 0, minute: 0)

    static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

/// When an upcoming schedule item happens, relative to now, in the employee's saved zone.
enum UpcomingLabel: Hashable, Sendable {
    /// In progress. `until` is the local end time, `nil` when the end is unknown.
    case now(until: ClockTime?)
    /// Starts within the hour; 0 means it starts this minute.
    case inMinutes(Int)
    /// Starts within `TimeLabels.relativeHours` hours.
    case inHours(Int, minutes: Int)
    case todayAt(ClockTime)
    case tomorrowAt(ClockTime)
    case onDayAt(CalendarDate, ClockTime)
    case allDayToday
    case allDayTomorrow
    case allDayOn(CalendarDate)
}

/// How long ago something happened, following the chat list's relative timestamp rules (02 §4).
enum PastLabel: Hashable, Sendable {
    case justNow
    case minutesAgo(Int)
    case todayAt(ClockTime)
    case yesterday
    case onDate(CalendarDate)
}

/// The first line of a message preview, or what stands in for it.
enum MessageSnippet: Hashable, Sendable {
    case text(String)
    case photo
    case file(name: String?)
    case systemUpdate
    case deleted
    case none
}

/// Row text for an activity. Reactions are rewritten on the client (06 §A2); everything else
/// uses the server summary.
enum ActivitySummary: Hashable, Sendable {
    case server(String)
    /// "{actor} reacted {emoji} to one of your messages."; a blank actor reads "Someone".
    case reaction(actor: String?, emoji: String?)
    /// The server sent no summary.
    case fallback
}

enum ActivityFilter: String, CaseIterable, Hashable, Sendable {
    case all, mentions, replies, reactions
}

/// What the quiet line under the date says. It only appears when something is off.
enum QuietStatus: Hashable, Sendable {
    /// The device is offline; `since` is when the oldest shown data last synced.
    case offline(since: PastLabel?)
    /// Data older than `TodayAssembler.staleAfter` and no refresh running.
    case stale(since: PastLabel)
}

/// Everything the Today screen draws, in priority order: what needs the person now, the next
/// three schedule items, today's celebrations, then the activity feed.
struct TodayState: Equatable, Sendable {
    /// Today's date in the employee's saved zone.
    var date: CalendarDate?
    /// The zone every time on the screen is in, and whether it fell back to America/Chicago.
    var timeZone: TimeZone = .current
    var usesFallbackTimeZone = false
    /// Nothing is cached and the first load is still running: the skeleton (after ~300 ms).
    var isInitialLoad = true
    /// Nothing is cached and every source failed: the full error state with Try again.
    var loadError: WaiveraError?
    var quietStatus: QuietStatus?
    var isRefreshing = false
    var needsYou = NeedsYouSection()
    var nextUp = NextUpSection()
    var celebrations: [CelebrationItem] = []
    var celebrationsFailed = false
    var activity = ActivitySection()

    /// The one "All caught up" moment: nothing needs the person and no activity is unread.
    var isAllCaughtUp: Bool {
        !isInitialLoad && loadError == nil && needsYou.isReady && needsYou.items.isEmpty
            && activity.isReady && activity.unreadCount == 0
    }
}

struct NeedsYouSection: Equatable, Sendable {
    static let collapsedCount = 5

    var items: [NeedsYouItem] = []
    /// Rows beyond `collapsedCount` are hidden until the person expands the section.
    var hiddenCount = 0
    var isExpanded = false
    var isReady = false
    var failed = false
}

enum NeedsYouItem: Hashable, Sendable, Identifiable {
    case directMessage(DirectMessageItem)
    case mention(MentionItem)
    case invitation(InvitationItem)
    /// Unread updates in the automated Waivera conversation (ticket cards).
    case ticket(TicketItem)

    var id: String {
        switch self {
        case .directMessage(let item): "dm-\(item.conversationId)"
        case .mention(let item): "mention-\(item.activityId)"
        case .invitation(let item): "invite-\(item.eventId)"
        case .ticket(let item): "ticket-\(item.conversationId)"
        }
    }
}

struct DirectMessageItem: Hashable, Sendable {
    var conversationId: Int
    /// `nil` when the server sent no usable name.
    var name: String?
    var snippet: MessageSnippet
    var unreadCount: Int
    var when: PastLabel?
}

struct MentionItem: Hashable, Sendable {
    var activityId: Int64
    var destination: ChatDestination
    var summary: ActivitySummary
    var when: PastLabel?
}

struct InvitationItem: Hashable, Sendable {
    var eventId: String
    var title: String?
    var organizer: String?
    var time: UpcomingLabel?
}

struct TicketItem: Hashable, Sendable {
    var conversationId: Int
    /// The ticket card's number and title when the newest message is one (03 §15).
    var ticketNumber: String?
    var ticketTitle: String?
    var snippet: MessageSnippet
    var unreadCount: Int
    var when: PastLabel?
}

struct NextUpSection: Equatable, Sendable {
    static let count = 3

    var items: [NextUpItem] = []
    var isReady = false
    var failed = false
}

struct NextUpItem: Hashable, Sendable, Identifiable {
    var eventId: String
    var title: String?
    var time: UpcomingLabel
    /// Clock times in the employee's zone; `nil` for all-day items.
    var start: ClockTime?
    var end: ClockTime?
    var endsOnLaterDay: Bool
    var location: String?
    var isOnline: Bool

    var id: String { eventId }

    var isHappeningNow: Bool {
        if case .now = time { return true }
        return false
    }

    /// Happening now or within the hour: the row is tinted so it stands out.
    var isSoon: Bool {
        if case .inMinutes = time { return true }
        return isHappeningNow
    }
}

struct CelebrationItem: Hashable, Sendable, Identifiable {
    var userId: String
    var name: String?
    var isBirthday: Bool
    /// Set when today is a work anniversary of one year or more.
    var anniversaryYears: Int?

    var id: String { userId }
}

struct ActivitySection: Equatable, Sendable {
    var rows: [ActivityRow] = []
    var filter: ActivityFilter = .all
    var unreadOnly = false
    var query = ""
    /// Unread across every loaded page, including mentions pinned under Needs you.
    var unreadCount = 0
    /// True when older pages may still hold unread items, so the badge reads "N+".
    var unreadIsLowerBound = false
    /// Activities across loaded pages before filtering (pinned mentions excluded).
    var totalCount = 0
    var hasMore = false
    var isLoadingMore = false
    var loadMoreFailed = false
    var isMarkingAllRead = false
    var isReady = false
    var failed = false

    /// Nothing at all, not even with filters off.
    var isEmpty: Bool { isReady && totalCount == 0 }

    /// Activities exist but the chips or the search hide all of them.
    var isFilteredEmpty: Bool { isReady && totalCount > 0 && rows.isEmpty }

    var isFiltered: Bool { filter != .all || unreadOnly || !query.isEmpty }
}

struct ActivityRow: Hashable, Sendable, Identifiable {
    var id: Int64
    var kind: ActivityItem.Kind
    var summary: ActivitySummary
    var when: PastLabel?
    var isRead: Bool
    var destination: ChatDestination
}
