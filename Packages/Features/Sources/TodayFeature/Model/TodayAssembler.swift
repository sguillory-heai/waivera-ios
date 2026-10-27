import Foundation
import WaiveraAPI
import WaiveraData

/// The repository streams Today renders from, as last received. `schedule` is one resource per
/// observed week, empty until the employee's date is known.
struct TodaySources: Sendable {
    var conversations = Resource<[Conversation]>()
    var activity = Resource<ActivityFeed>()
    var schedule: [Resource<CalendarFeed>] = []
    var milestones = Resource<MilestoneIndex>()
}

/// What the activity list has done locally on top of the cached feed: chips, search, paging
/// and optimistic reads.
struct ActivityLocalState: Equatable, Sendable {
    var filter: ActivityFilter = .all
    var unreadOnly = false
    var query = ""
    /// Rows marked read on this screen whose request has not finished yet.
    var readingIds: Set<Int64> = []
    var isMarkingAllRead = false
    var isLoadingMore = false
    var loadMoreFailed = false
    /// Set when the automatic loader stopped at its page cap while unread items may remain.
    var autoPagingCapped = false

    func isRead(_ item: ActivityItem) -> Bool {
        item.isRead || isMarkingAllRead || readingIds.contains(item.id)
    }
}

/// What Today has done locally on top of the cached data.
struct TodayLocalState: Equatable, Sendable {
    var needsYouExpanded = false
    /// Invitations answered optimistically; they leave Needs you at once and return if the call fails.
    var answeredInvitations: Set<String> = []
    var isRefreshing = false
}

/// Who, where and when the screen is rendered for.
struct TodayContext: Sendable {
    var zone: TimeZone
    var usesFallbackTimeZone = false
    var now: Date
    var connection: ConnectionBanner = .hidden
    var local = TodayLocalState()
    var activity = ActivityLocalState()
}

/// Loading, ready and failed for one source, whatever its value type.
struct SourceStatus: Sendable {
    var hasContent: Bool
    var isReady: Bool
    var updatedAt: Date?
    var error: WaiveraError?

    var isLoading: Bool { !isReady && error == nil }
    var failed: Bool { !isReady && error != nil }

    init<Value>(_ resource: Resource<Value>, hasContent: (Value) -> Bool) {
        let content = resource.value.map(hasContent) ?? false
        self.hasContent = content
        isReady = content || resource.updatedAt != nil || resource.phase == .loaded
        updatedAt = resource.updatedAt
        error = resource.error
    }

    /// Several weeks of the schedule read as one source: ready once every week is, or as soon as
    /// any week has something to show.
    init(weeks: [Resource<CalendarFeed>]) {
        let parts = weeks.map { SourceStatus($0) { !$0.isEmpty } }
        hasContent = parts.contains(where: \.hasContent)
        isReady = hasContent || (!parts.isEmpty && parts.allSatisfy(\.isReady))
        updatedAt = parts.allSatisfy { $0.updatedAt != nil } ? parts.compactMap(\.updatedAt).min() : nil
        error = parts.first(where: \.failed)?.error
    }
}

/// Builds `TodayState` from the sources. Pure, so every rule is unit tested on Linux.
enum TodayAssembler {
    /// Data older than this gets the quiet "Updated N min ago" line.
    static let staleAfter: TimeInterval = 5 * 60

    static func assemble(
        _ sources: TodaySources,
        context: TodayContext,
        summaryText: (ActivitySummary) -> String = TodayStrings.summary
    ) -> TodayState {
        let today = CalendarDate(context.now, in: context.zone)
        let chats = SourceStatus(sources.conversations) { !$0.isEmpty }
        let feed = SourceStatus(sources.activity) { !$0.items.isEmpty }
        let schedule = SourceStatus(weeks: sources.schedule)
        let primary = [chats, feed, schedule]
        let nothingCached = !primary.contains(where: \.hasContent)
        let stillLoading = primary.contains(where: \.isLoading)

        let pinned = pinnedMentions(sources, context: context)
        let events = ScheduleRules.events(in: sources.schedule.compactMap(\.value))
        let milestones = SourceStatus(sources.milestones) { !$0.milestones.isEmpty }

        var state = TodayState()
        state.date = today
        state.timeZone = context.zone
        state.usesFallbackTimeZone = context.usesFallbackTimeZone
        state.isInitialLoad = nothingCached && stillLoading
        state.loadError = nothingCached && !stillLoading ? primary.compactMap(\.error).first : nil
        state.quietStatus = quietStatus(primary, context: context)
        state.isRefreshing = context.local.isRefreshing
        state.needsYou = needsYou(sources, status: chats, events: events, pinned: pinned, context: context)
        state.nextUp = NextUpSection(
            items: schedule.isReady ? ScheduleRules.nextUp(events, now: context.now, zone: context.zone) : [],
            isReady: schedule.isReady,
            failed: schedule.failed
        )
        state.celebrations = ScheduleRules.celebrations(sources.milestones.value ?? .empty, on: today)
        state.celebrationsFailed = milestones.error != nil && !milestones.hasContent
        state.activity = ActivityAssembler.section(
            sources.activity,
            local: context.activity,
            now: context.now,
            zone: context.zone,
            excluding: Set(pinned.map(\.id)),
            summaryText: summaryText
        )
        return state
    }

    // MARK: Needs you

    /// Unread mentions shown under Needs you (and therefore left out of the feed below). A mention
    /// inside a direct conversation that is already listed as unread is not repeated.
    static func pinnedMentions(_ sources: TodaySources, context: TodayContext) -> [ActivityItem] {
        let unreadDirects = Set(unreadConversations(sources, kind: .direct).map(\.id))
        return ActivityRules.merge(sources.activity.value?.items ?? []).filter {
            $0.kind == .mention && !context.activity.isRead($0) && !unreadDirects.contains($0.conversationId)
        }
    }

    private static func needsYou(
        _ sources: TodaySources,
        status: SourceStatus,
        events: [CalendarEvent],
        pinned: [ActivityItem],
        context: TodayContext
    ) -> NeedsYouSection {
        let invitations = ScheduleRules.invitations(
            events,
            now: context.now,
            zone: context.zone,
            answered: context.local.answeredInvitations
        ).map(NeedsYouItem.invitation)
        let all = messages(sources, pinned: pinned, context: context) + invitations + tickets(sources, context: context)
        let expanded = context.local.needsYouExpanded
        let visible = expanded ? all : Array(all.prefix(NeedsYouSection.collapsedCount))
        return NeedsYouSection(
            items: visible,
            hiddenCount: all.count - visible.count,
            isExpanded: expanded && all.count > NeedsYouSection.collapsedCount,
            isReady: status.isReady,
            failed: status.failed
        )
    }

    /// Unread direct messages and pinned mentions, newest first; undated ones last.
    private static func messages(_ sources: TodaySources, pinned: [ActivityItem], context: TodayContext)
        -> [NeedsYouItem]
    {
        let directs: [(Date?, NeedsYouItem)] = unreadConversations(sources, kind: .direct).map { conversation in
            let item = DirectMessageItem(
                conversationId: conversation.id,
                name: personName(conversation),
                snippet: snippet(conversation.preview),
                unreadCount: conversation.unreadCount,
                when: past(conversation.lastMessage?.createdAt, context: context)
            )
            return (conversation.lastMessage?.createdAt, .directMessage(item))
        }
        let mentions: [(Date?, NeedsYouItem)] = pinned.map { activity in
            let item = MentionItem(
                activityId: activity.id,
                destination: activity.destination,
                summary: ActivityRules.summary(activity),
                when: past(activity.createdAt, context: context)
            )
            return (activity.createdAt, .mention(item))
        }
        return (directs + mentions).sorted { lhs, rhs in
            switch (lhs.0, rhs.0) {
            case (let left?, let right?): left > right
            case (.some, nil): true
            default: false
            }
        }
        .map(\.1)
    }

    /// Unread updates in the automated Waivera conversation, with the ticket card's number and title.
    private static func tickets(_ sources: TodaySources, context: TodayContext) -> [NeedsYouItem] {
        unreadConversations(sources, kind: .bot).map { conversation in
            let ticket = conversation.lastMessage?.ticket
            return NeedsYouItem.ticket(
                TicketItem(
                    conversationId: conversation.id,
                    ticketNumber: ticket?.ticketId,
                    ticketTitle: ticket?.title,
                    snippet: snippet(conversation.preview),
                    unreadCount: conversation.unreadCount,
                    when: past(conversation.lastMessage?.createdAt, context: context)
                )
            )
        }
    }

    private static func past(_ date: Date?, context: TodayContext) -> PastLabel? {
        date.map { TimeLabels.past($0, now: context.now, zone: context.zone) }
    }

    private static func unreadConversations(_ sources: TodaySources, kind: Conversation.Kind) -> [Conversation] {
        (sources.conversations.value ?? []).filter { $0.kind == kind && $0.unreadCount > 0 && !$0.isArchived }
    }

    private static func personName(_ conversation: Conversation) -> String? {
        if case .person(let name) = conversation.title { return name?.trimmedNonEmpty }
        return nil
    }

    /// The preview's first line, else what the attachment is (02 §4 preview rules).
    static func snippet(_ preview: ConversationPreview) -> MessageSnippet {
        switch preview {
        case .text(let text): .text(text)
        case .photo: .photo
        case .file(let name): .file(name: name)
        case .systemUpdate: .systemUpdate
        case .deleted: .deleted
        case .noMessages, .blank: .none
        }
    }

    // MARK: Quiet line

    /// Offline always says so; otherwise "Updated N min ago" only when the oldest source is
    /// older than `staleAfter` and no refresh is running.
    private static func quietStatus(_ sources: [SourceStatus], context: TodayContext) -> QuietStatus? {
        let oldest = sources.compactMap(\.updatedAt).min()
        let since = oldest.map { TimeLabels.past($0, now: context.now, zone: context.zone) }
        if context.connection == .offline { return .offline(since: since) }
        guard let oldest, let since, !context.local.isRefreshing,
            context.now.timeIntervalSince(oldest) >= staleAfter
        else { return nil }
        return .stale(since: since)
    }
}

/// The activity section, shared by Today and the full Activity screen.
enum ActivityAssembler {
    static func section(
        _ resource: Resource<ActivityFeed>,
        local: ActivityLocalState,
        now: Date,
        zone: TimeZone,
        excluding pinned: Set<Int64> = [],
        summaryText: (ActivitySummary) -> String = TodayStrings.summary
    ) -> ActivitySection {
        let status = SourceStatus(resource) { !$0.items.isEmpty }
        let merged = ActivityRules.merge(resource.value?.items ?? [])
        let listed = merged.filter { !pinned.contains($0.id) }
        let rows = listed.compactMap { item -> ActivityRow? in
            let isRead = local.isRead(item)
            guard
                ActivityRules.matches(
                    kind: item.kind,
                    isRead: isRead,
                    filter: local.filter,
                    unreadOnly: local.unreadOnly
                )
            else { return nil }
            let summary = ActivityRules.summary(item)
            guard
                ActivityRules.matches(
                    query: local.query,
                    summaryText: summaryText(summary),
                    actor: item.actorDisplayName
                )
            else { return nil }
            return ActivityRow(
                id: item.id,
                kind: item.kind,
                summary: summary,
                when: item.createdAt.map { TimeLabels.past($0, now: now, zone: zone) },
                isRead: isRead,
                destination: item.destination
            )
        }
        // Has-more from a cold cache means nothing until a real sync confirmed it.
        let hasMore = (resource.value?.hasMore ?? false) && resource.updatedAt != nil
        let mayHoldMore = ActivityRules.olderPagesMayHoldUnread(merged, hasMore: hasMore, isRead: local.isRead)
        return ActivitySection(
            rows: rows,
            filter: local.filter,
            unreadOnly: local.unreadOnly,
            query: local.query,
            unreadCount: merged.filter { !local.isRead($0) }.count,
            unreadIsLowerBound: mayHoldMore && local.autoPagingCapped,
            totalCount: listed.count,
            hasMore: hasMore,
            isLoadingMore: local.isLoadingMore || (resource.value?.isLoadingMore ?? false),
            loadMoreFailed: local.loadMoreFailed,
            isMarkingAllRead: local.isMarkingAllRead,
            isReady: status.isReady,
            failed: status.failed
        )
    }
}
