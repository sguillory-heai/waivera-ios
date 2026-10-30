import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import TodayFeature

/// The pure rules behind the Today list: what needs the person, Next up, celebrations, the
/// activity section and the screen states.
struct TodayAssemblerTests {
    private func assemble(_ sources: TodaySources = Fixture.sources(), _ context: TodayContext = Fixture.context())
        -> TodayState
    {
        TodayAssembler.assemble(sources, context: context)
    }

    // MARK: Needs you

    @Test func unreadDirectsMentionsInvitationsAndTicketUpdatesNeedYou() {
        var group = Fixture.direct(11, unread: 4)
        group.kind = .group
        let state = assemble(
            Fixture.sources(
                conversations: [
                    Fixture.direct(7, unread: 2, at: "2026-11-01T16:00:00Z"),
                    group,
                    Fixture.bot(14, unread: 1),
                    Fixture.channel(20),
                    Fixture.direct(8, unread: 0),
                    Fixture.direct(9, unread: 3, archived: true),
                ],
                activity: [
                    Fixture.activity(1, .mention, at: "2026-11-01T16:10:00Z", conversation: 11),
                    Fixture.activity(2, .mention, isRead: true, conversation: 11),
                    Fixture.activity(3, .threadReply, conversation: 11),
                ],
                events: [
                    Fixture.event("invite", "2026-11-02T15:00:00Z", "2026-11-02T16:00:00Z", response: .pending),
                    Fixture.event("started", "2026-11-01T16:00:00Z", "2026-11-01T17:00:00Z", response: .pending),
                    Fixture.event(
                        "mine",
                        "2026-11-02T15:00:00Z",
                        "2026-11-02T16:00:00Z",
                        response: .pending,
                        isOwner: true
                    ),
                ]
            )
        )
        #expect(state.needsYou.items.map(\.id) == ["mention-1", "dm-7", "invite-invite"], "folds after three")
        #expect(state.needsYou.totalCount == 4)
        #expect(state.needsYou.kinds == [.mention: 1, .message: 1, .invitation: 1, .ticket: 1])
        let all = TodayAssembler.assemble(
            Fixture.sources(
                conversations: [Fixture.direct(7, unread: 2, at: "2026-11-01T16:00:00Z"), Fixture.bot(14, unread: 1)]
            ),
            context: Fixture.context()
        )
        guard case .ticket(let ticket) = all.needsYou.items.last else {
            Issue.record("the last row is not a ticket")
            return
        }
        #expect(ticket.ticketNumber == "4821")
        #expect(ticket.ticketTitle == "Wheelchair ramp repair")
        guard case .invitation(let invite) = state.needsYou.items[2] else {
            Issue.record("the third row is not an invitation")
            return
        }
        #expect(invite.time == .tomorrowAt(ClockTime(hour: 9, minute: 0)))
    }

    @Test func aPinnedMentionIsNotRepeatedInTheFeedButTheBadgeStillCountsIt() {
        let state = assemble(
            Fixture.sources(activity: [Fixture.activity(1, .mention, conversation: 11), Fixture.activity(2, .reaction)])
        )
        #expect(state.activity.rows.map(\.id) == [2])
        #expect(state.activity.unreadCount == 2)
        #expect(state.activity.totalCount == 1)
    }

    @Test func aMentionInsideAnUnreadDirectStaysInTheFeedInsteadOfBeingListedTwice() {
        let state = assemble(
            Fixture.sources(
                conversations: [Fixture.direct(7, unread: 1)],
                activity: [Fixture.activity(1, .mention, conversation: 7)]
            )
        )
        #expect(state.needsYou.items.map(\.id) == ["dm-7"])
        #expect(state.activity.rows.map(\.id) == [1])
    }

    @Test func anAnsweredInvitationLeavesNeedsYouAtOnce() {
        let events = [Fixture.event("invite", "2026-11-02T15:00:00Z", "2026-11-02T16:00:00Z", response: .pending)]
        let local = TodayLocalState(answeredInvitations: ["invite"])
        #expect(assemble(Fixture.sources(events: events), Fixture.context(local: local)).needsYou.items.isEmpty)
    }

    @Test func needsYouCollapsesToThreeRowsWithACountOfTheRest() {
        let conversations = (1...7).map { index in
            Fixture.direct(index, unread: 1, at: WaiveraInstant.format(Fixture.now - Double(index * 60)))
        }
        let collapsed = assemble(Fixture.sources(conversations: conversations)).needsYou
        #expect(collapsed.items.count == 3)
        #expect(collapsed.hiddenCount == 4)
        #expect(collapsed.totalCount == 7, "the hero counts the folded rows too")
        #expect(!collapsed.isExpanded)
        #expect(collapsed.items.first?.id == "dm-1")

        let expanded = assemble(
            Fixture.sources(conversations: conversations),
            Fixture.context(local: TodayLocalState(needsYouExpanded: true))
        ).needsYou
        #expect(expanded.items.count == 7)
        #expect(expanded.hiddenCount == 0)
        #expect(expanded.isExpanded)
    }

    @Test func directSnippetsFallBackToTheAttachmentWhenThereIsNoText() {
        var photo = Fixture.direct(7, text: nil)
        photo.lastMessage?.attachment = Attachment(url: "k/1", kind: .image, contentType: "image/jpeg")
        var file = Fixture.direct(8, text: "  \n", at: "2026-11-01T16:10:00Z")
        file.lastMessage?.attachment = Attachment(url: "k/2", kind: .file, name: "rota.pdf")
        let snippets = assemble(Fixture.sources(conversations: [photo, file])).needsYou.items.compactMap { item in
            if case .directMessage(let direct) = item { return direct.snippet }
            return nil
        }
        #expect(snippets == [.photo, .file(name: "rota.pdf")])
    }

    @Test func aDirectWithoutAUsableNameKeepsTheRowAndLetsTheScreenSayWho() {
        var conversation = Fixture.direct(7)
        conversation.participants = [ChatUser(id: Fixture.viewerId), ChatUser(id: "usr_7")]
        guard
            case .directMessage(let item) = assemble(Fixture.sources(conversations: [conversation])).needsYou.items
                .first
        else {
            Issue.record("no direct row")
            return
        }
        #expect(item.name == nil)
        #expect(item.otherUserId == "usr_7", "the photo still loads for the one other person")
    }

    @Test func aDirectWithMoreThanOneOtherPersonHasNoPhoto() {
        var conversation = Fixture.direct(7)
        conversation.participants = [ChatUser(id: Fixture.viewerId), ChatUser(id: "usr_7"), ChatUser(id: "usr_8")]
        guard
            case .directMessage(let item) = assemble(Fixture.sources(conversations: [conversation])).needsYou.items
                .first
        else {
            Issue.record("no direct row")
            return
        }
        #expect(item.otherUserId == nil)
    }

    // MARK: All caught up

    @Test func allCaughtUpWhenNothingNeedsYouAndNothingIsUnread() {
        #expect(assemble(Fixture.sources(activity: [Fixture.activity(1, isRead: true)])).isAllCaughtUp)
    }

    @Test func notCaughtUpWhileActivityIsUnreadOrBeforeTheFirstSync() {
        #expect(!assemble(Fixture.sources(activity: [Fixture.activity(1)])).isAllCaughtUp)
        let unsynced = TodaySources(
            conversations: Resource(phase: .loading),
            activity: Resource(phase: .loading),
            schedule: [Resource(phase: .loading), Resource(phase: .loading)]
        )
        #expect(!assemble(unsynced).isAllCaughtUp)
    }

    // MARK: Activity

    @Test func theUnreadCountCoversEveryLoadedPageAndIsALowerBoundOnlyPastTheCap() {
        let items = (1...60).map { Fixture.activity(Int64($0), isRead: $0 % 2 == 0) }
        let section = assemble(Fixture.sources(activity: items, hasMore: true)).activity
        #expect(section.unreadCount == 30)
        #expect(!section.unreadIsLowerBound)
        let capped = assemble(
            Fixture.sources(activity: items, hasMore: true),
            Fixture.context(activity: ActivityLocalState(autoPagingCapped: true))
        )
        #expect(capped.activity.unreadIsLowerBound)
    }

    @Test func aRowBeingMarkedReadShowsReadUntilTheRequestSettles() {
        let local = ActivityLocalState(readingIds: [1])
        let state = assemble(Fixture.sources(activity: [Fixture.activity(1)]), Fixture.context(activity: local))
        #expect(state.activity.rows.first?.isRead == true)
        #expect(state.activity.unreadCount == 0)
    }

    @Test func withUnreadOnReadingTheLastUnreadItemShowsTheFilteredEmptyState() {
        let local = ActivityLocalState(unreadOnly: true)
        let before = assemble(
            Fixture.sources(activity: [Fixture.activity(1), Fixture.activity(2, isRead: true)]),
            Fixture.context(activity: local)
        )
        #expect(before.activity.rows.map(\.id) == [1])
        let after = assemble(
            Fixture.sources(activity: [Fixture.activity(1, isRead: true), Fixture.activity(2, isRead: true)]),
            Fixture.context(activity: local)
        )
        #expect(after.activity.isFilteredEmpty)
        #expect(!after.activity.isEmpty)
    }

    @Test func hasMoreIsOnlyTrustedAfterARealSync() {
        var cold = Fixture.sources(activity: [Fixture.activity(1)], hasMore: true)
        cold.activity.updatedAt = nil
        #expect(!assemble(cold).activity.hasMore)
        #expect(assemble(Fixture.sources(activity: [Fixture.activity(1)], hasMore: true)).activity.hasMore)
    }

    @Test func rowsOpenThreadsByTheirRootId() {
        let reply = Fixture.activity(1, conversation: 40, message: 9_334, threadRoot: 9_330)
        let row = assemble(Fixture.sources(activity: [reply])).activity.rows.first
        #expect(row?.destination == .thread(rootMessageId: 9_330, conversationId: 40, targetMessageId: 9_334))
    }

    // MARK: Screen states

    @Test func nothingCachedAndStillLoadingIsTheInitialLoad() {
        let loading = TodaySources(
            conversations: Resource(phase: .loading),
            activity: Resource(phase: .loading),
            schedule: [Resource(phase: .loading), Resource(phase: .loading)]
        )
        let state = assemble(loading)
        #expect(state.isInitialLoad)
        #expect(state.loadError == nil)

        var cachedChats = loading
        cachedChats.conversations = Resource(value: [Fixture.direct(7)], phase: .loading)
        #expect(!assemble(cachedChats).isInitialLoad, "cached chats render while the rest loads")
    }

    @Test func nothingCachedAndEverySourceFailedIsTheFullErrorState() {
        let failed = ResourcePhase.failed(.offline)
        let state = assemble(
            TodaySources(
                conversations: Resource(phase: failed),
                activity: Resource(phase: failed),
                schedule: [Resource(phase: failed), Resource(phase: failed)],
                milestones: Resource(phase: failed)
            )
        )
        #expect(state.loadError == .offline)
        #expect(!state.isInitialLoad)
        #expect(!state.isAllCaughtUp)
    }

    @Test func cachedDataWithAFailedRefreshKeepsTheContentAndNoFullError() {
        var sources = Fixture.sources(conversations: [Fixture.direct(7)])
        sources.conversations.phase = .failed(.offline)
        let state = assemble(sources)
        #expect(state.loadError == nil)
        #expect(state.needsYou.items.count == 1)
    }

    @Test func theStaleLineAppearsOnlyWhenDataIsOlderThanFiveMinutesAndNoRefreshIsRunning() {
        #expect(assemble(Fixture.sources(at: Fixture.now - 240)).quietStatus == nil)
        #expect(assemble(Fixture.sources(at: Fixture.now - 720)).quietStatus == .stale(since: .minutesAgo(12)))
        let refreshing = Fixture.context(local: TodayLocalState(isRefreshing: true))
        #expect(assemble(Fixture.sources(at: Fixture.now - 720), refreshing).quietStatus == nil)
    }

    @Test func offlineShowsTheQuietLineAndReconnectingLeavesItToTheShellBanner() {
        let sources = Fixture.sources(at: Fixture.now - 120)
        #expect(assemble(sources, Fixture.context(connection: .offline)).quietStatus == .offline(since: .minutesAgo(2)))
        #expect(assemble(sources, Fixture.context(connection: .reconnecting(attempt: 2))).quietStatus == nil)
        #expect(assemble(sources, Fixture.context(connection: .connecting)).quietStatus == nil)
    }

    @Test func theScreenDateIsTheEmployeesDateNotUTC() {
        // 03:00 UTC on 1 Nov is 22:00 CDT on 31 Oct.
        let state = assemble(Fixture.sources(), Fixture.context(now: Fixture.instant("2026-11-01T03:00:00Z")))
        #expect(state.date == Fixture.date(2026, 10, 31))
        #expect(
            ScheduleRules.weekAnchors(today: Fixture.date(2026, 10, 31)) == [
                Fixture.date(2026, 10, 31), Fixture.date(2026, 11, 7),
            ]
        )
    }
}
