#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// What the schedule screen can ask for. Main-actor closures, called from buttons only;
    /// pull to refresh is separate because SwiftUI runs it off the main actor.
    public struct ScheduleActions: Sendable {
        public var selectView: @MainActor @Sendable (CalendarPeriod) -> Void
        public var selectDate: @MainActor @Sendable (CalendarDate) -> Void
        public var step: @MainActor @Sendable (Int) -> Void
        public var goToToday: @MainActor @Sendable () -> Void
        public var retry: @MainActor @Sendable () -> Void
        public var retryMilestones: @MainActor @Sendable () -> Void
        public var openEvent: @MainActor @Sendable (String) -> Void
        /// "Send wishes" on a celebration card, with the celebrant's user id.
        public var sendWishes: @MainActor @Sendable (String) -> Void

        public init(
            selectView: @escaping @MainActor @Sendable (CalendarPeriod) -> Void = { _ in },
            selectDate: @escaping @MainActor @Sendable (CalendarDate) -> Void = { _ in },
            step: @escaping @MainActor @Sendable (Int) -> Void = { _ in },
            goToToday: @escaping @MainActor @Sendable () -> Void = {},
            retry: @escaping @MainActor @Sendable () -> Void = {},
            retryMilestones: @escaping @MainActor @Sendable () -> Void = {},
            openEvent: @escaping @MainActor @Sendable (String) -> Void = { _ in },
            sendWishes: @escaping @MainActor @Sendable (String) -> Void = { _ in }
        ) {
            self.selectView = selectView
            self.selectDate = selectDate
            self.step = step
            self.goToToday = goToToday
            self.retry = retry
            self.retryMilestones = retryMilestones
            self.openEvent = openEvent
            self.sendWishes = sendWishes
        }
    }
#endif
