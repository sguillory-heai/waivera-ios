#if DEBUG
    import Foundation
    import WaiveraAPI
    import WaiveraData
    import WaiveraTestSupport

    /// Every screen state, built from the demo data through the same builders the models use, for
    /// previews and snapshot tests (DEBUG only). "Today" is the demo day: 1 Nov 2026 in Chicago,
    /// the day DST ends.
    public enum SchedulePreviewStates {
        public enum Schedule: String, CaseIterable, Sendable {
            case month, week, day, loading, empty, error, refreshFailed, milestonesFailed, fallbackZone, otherDay
        }

        public enum Event: String, CaseIterable, Sendable {
            case pendingInvitation, accepted, saving, responseFailed, organizer, joinOpen, joinFailed
            case started, allDay, loading, notFound, error, refreshFailed
        }

        static let data = DemoData.make()
        static let locale = Locale(identifier: "en_US")

        public static func schedule(_ variant: Schedule) -> ScheduleUIState {
            let zone = ScheduleZone.resolve(
                savedIdentifier: variant == .fallbackZone ? nil : data.user.timeZoneIdentifier
            )
            let today = DemoData.today
            let view: CalendarPeriod =
                switch variant {
                case .week: .week
                case .day: .day
                default: .month
                }
            let selected = variant == .otherDay ? today.adding(days: 4) : today
            let interval = SchedulePeriods.fetchInterval(view, containing: selected, in: zone.timeZone)
            let loaded = Resource(value: slice(interval, zone: zone.timeZone), phase: .loaded, updatedAt: DemoData.now)
            let feed: Resource<CalendarFeed>? =
                switch variant {
                case .loading: Resource(phase: .loading)
                case .empty: Resource(value: CalendarFeed(), phase: .loaded, updatedAt: DemoData.now)
                case .error: Resource(phase: .failed(.server(statusCode: 503)))
                case .refreshFailed: Resource(value: loaded.value, phase: .failed(.offline), updatedAt: DemoData.now)
                default: loaded
                }
            return ScheduleStateBuilder(
                view: view,
                selectedDate: selected,
                today: today,
                zone: zone,
                deviceZone: zone.timeZone,
                feed: feed,
                milestones: variant == .empty ? .empty : MilestoneCalendar(MilestoneIndex(data.milestones)),
                milestonesFailed: variant == .milestonesFailed,
                isOffline: false
            ).build(text: ScheduleText(zone: zone.timeZone, locale: locale))
        }

        public static func event(_ variant: Event) -> EventUIState {
            switch variant {
            case .loading: return .loading
            case .notFound: return .notFound
            case .error: return .error(.server(statusCode: 503))
            default: break
            }
            let (id, offset) = moment(for: variant)
            guard let event = data.calendar.events.first(where: { $0.id == id }) else { return .notFound }
            let zone = ScheduleZone.resolve(savedIdentifier: data.user.timeZoneIdentifier)
            let formatter = EventDetailsFormatter(
                zone: zone,
                deviceZone: zone.timeZone,
                now: DemoData.now.addingTimeInterval(offset),
                myUserId: data.user.id,
                milestones: MilestoneCalendar(MilestoneIndex(data.milestones))
            )
            return .loaded(
                formatter.details(
                    event,
                    interaction: interaction(for: variant),
                    refreshFailed: variant == .refreshFailed,
                    text: ScheduleText(zone: zone.timeZone, locale: locale)
                )
            )
        }

        /// Which demo event a state shows, and how far after the demo morning it is viewed.
        private static func moment(for variant: Event) -> (id: String, offset: TimeInterval) {
            switch variant {
            case .organizer: ("evt_demo_checkin", 0)
            case .allDay: ("evt_demo_allday", 0)
            // Five minutes before the 14:00 CST check-in, inside the join window.
            case .joinOpen, .joinFailed: ("evt_demo_checkin", 4 * 3_600 + 55 * 60)
            // Just after the 10:00 CST invite started: the answer can no longer change.
            case .started: ("evt_demo_invite", 3_700)
            default: ("evt_demo_invite", 0)
            }
        }

        private static func interaction(for variant: Event) -> EventInteraction {
            var interaction = EventInteraction()
            switch variant {
            case .accepted: interaction.optimistic = OptimisticResponse(accept: true, phase: .undoWindow)
            case .saving: interaction.optimistic = OptimisticResponse(accept: true, phase: .saving)
            case .responseFailed: interaction.failure = ResponseFailure(accept: true, error: .offline)
            case .joinFailed: interaction.joinError = .noLink
            default: break
            }
            return interaction
        }

        private static func slice(_ interval: DateInterval, zone: TimeZone) -> CalendarFeed {
            let first = CalendarDate(interval.start, in: zone)
            let last = CalendarDate(interval.end.addingTimeInterval(-1), in: zone)
            let feed = data.calendar
            return CalendarFeed(
                events: feed.events.filter { event in
                    if let allDay = event.allDay { return allDay.start <= last && allDay.endExclusive > first }
                    return event.start < interval.end && event.end > interval.start
                },
                timeOff: feed.timeOff.filter { $0.start < interval.end && $0.end > interval.start },
                holidays: feed.holidays.filter { $0.start <= last && $0.end >= first }
            )
        }
    }
#endif
