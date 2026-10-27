#if DEBUG
    import Foundation
    import WaiveraAPI
    import WaiveraData

    /// Fixed screen states for previews and snapshot tests. Times are the demo "today":
    /// Sunday 1 November 2026 in America/Chicago, the day DST ends.
    enum TodayPreviewStates {
        static let zone = TimeZone(identifier: "America/Chicago") ?? .current
        /// 09:00 CST on 1 November 2026, the demo data's "now".
        static let now = Date(timeIntervalSince1970: 1_793_545_200)
        static let today = CalendarDate(now, in: zone)

        static func populated() -> TodayState {
            var state = base()
            state.needsYou = NeedsYouSection(items: needsYouItems, hiddenCount: 2, isReady: true)
            state.nextUp = NextUpSection(items: nextUpItems, isReady: true)
            state.celebrations = celebrationItems
            state.activity = ActivitySection(
                rows: activityRows,
                unreadCount: 3,
                totalCount: 3,
                hasMore: true,
                isReady: true
            )
            return state
        }

        static func caughtUp() -> TodayState {
            var state = base()
            state.needsYou = NeedsYouSection(isReady: true)
            state.nextUp = NextUpSection(isReady: true)
            state.activity = ActivitySection(
                rows: [
                    ActivityRow(
                        id: 603,
                        kind: .mention,
                        summary: .server("Jordan Lee mentioned you in #care-team."),
                        when: .yesterday,
                        isRead: true,
                        destination: .conversation(id: 12, targetMessageId: 9320)
                    )
                ],
                totalCount: 1,
                isReady: true
            )
            return state
        }

        static func offline() -> TodayState {
            var state = populated()
            state.quietStatus = .offline(since: .minutesAgo(18))
            state.activity.loadMoreFailed = true
            state.celebrationsFailed = true
            state.celebrations = []
            return state
        }

        static func stale() -> TodayState {
            var state = populated()
            state.quietStatus = .stale(since: .todayAt(ClockTime(hour: 8, minute: 2)))
            return state
        }

        static func sectionErrors() -> TodayState {
            var state = base()
            state.needsYou = NeedsYouSection(failed: true)
            state.nextUp = NextUpSection(failed: true)
            state.celebrationsFailed = true
            state.activity = ActivitySection(failed: true)
            return state
        }

        static func failed() -> TodayState {
            var state = base()
            state.loadError = .offline
            return state
        }

        static func loading() -> TodayState {
            var state = base()
            state.isInitialLoad = true
            return state
        }

        static func filteredEmpty() -> TodayState {
            var state = caughtUp()
            state.activity.unreadOnly = true
            state.activity.rows = []
            return state
        }

        static func fallbackZone() -> TodayState {
            var state = populated()
            state.usesFallbackTimeZone = true
            return state
        }

        static func activityScreen() -> ActivityScreenState {
            var screen = ActivityScreenState()
            screen.isInitialLoad = false
            screen.section = populated().activity
            return screen
        }

        private static let needsYouItems: [NeedsYouItem] = [
            .directMessage(
                DirectMessageItem(
                    conversationId: 7,
                    name: "Priya Raman",
                    snippet: .text("Can you cover the Thursday afternoon visit at the Lakeview home?"),
                    unreadCount: 2,
                    when: .minutesAgo(5)
                )
            ),
            .mention(
                MentionItem(
                    activityId: 501,
                    destination: .thread(rootMessageId: 9330, conversationId: 12, targetMessageId: 9333),
                    summary: .server(
                        "Jordan Lee mentioned you in #care-team: @Alex can you confirm the meds list?"
                    ),
                    when: .todayAt(ClockTime(hour: 8, minute: 12))
                )
            ),
            .invitation(
                InvitationItem(
                    eventId: "evt_review",
                    title: "Care plan review",
                    organizer: "Priya Raman",
                    time: .tomorrowAt(ClockTime(hour: 9, minute: 0))
                )
            ),
            .ticket(
                TicketItem(
                    conversationId: 14,
                    ticketNumber: "4821",
                    ticketTitle: "Wheelchair ramp repair",
                    snippet: .text("Status changed to In progress"),
                    unreadCount: 1,
                    when: .yesterday
                )
            ),
        ]

        private static let nextUpItems: [NextUpItem] = [
            NextUpItem(
                eventId: "evt_shift",
                title: "Overnight shift",
                time: .now(until: ClockTime(hour: 10, minute: 0)),
                start: ClockTime(hour: 22, minute: 0),
                end: ClockTime(hour: 10, minute: 0),
                endsOnLaterDay: true,
                location: "Lakeview home",
                isOnline: false
            ),
            NextUpItem(
                eventId: "evt_visit",
                title: "Client home visit",
                time: .inMinutes(25),
                start: ClockTime(hour: 9, minute: 25),
                end: ClockTime(hour: 10, minute: 30),
                endsOnLaterDay: false,
                location: "1200 W Lake St",
                isOnline: false
            ),
            NextUpItem(
                eventId: "evt_dst",
                title: "Daylight saving ends",
                time: .allDayToday,
                start: nil,
                end: nil,
                endsOnLaterDay: false,
                location: nil,
                isOnline: false
            ),
        ]

        private static let celebrationItems: [CelebrationItem] = [
            CelebrationItem(userId: "usr_jordan_lee", name: "Jordan Lee", isBirthday: false, anniversaryYears: 5),
            CelebrationItem(userId: "usr_sam_ortiz", name: "Sam Ortiz", isBirthday: true, anniversaryYears: nil),
        ]

        private static let activityRows: [ActivityRow] = [
            ActivityRow(
                id: 601,
                kind: .reaction,
                summary: .reaction(actor: "Dana", emoji: "🎉"),
                when: .minutesAgo(12),
                isRead: false,
                destination: .conversation(id: 7, targetMessageId: 9312)
            ),
            ActivityRow(
                id: 602,
                kind: .threadReply,
                summary: .server("Sam Ortiz replied in a thread: Thanks, I'll bring the forms."),
                when: .todayAt(ClockTime(hour: 7, minute: 40)),
                isRead: false,
                destination: .thread(rootMessageId: 9330, conversationId: 7, targetMessageId: 9334)
            ),
            ActivityRow(
                id: 603,
                kind: .unknown,
                summary: .server("Your shift swap was approved."),
                when: .onDate(today.adding(days: -3)),
                isRead: true,
                destination: .conversation(id: 9, targetMessageId: 9401)
            ),
        ]

        private static func base() -> TodayState {
            var state = TodayState()
            state.date = today
            state.timeZone = zone
            state.isInitialLoad = false
            return state
        }
    }
#endif
