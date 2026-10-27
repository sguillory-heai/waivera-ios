import Foundation
import WaiveraAPI
import WaiveraData

/// "Now" for the schedule screens when no clock is injected. `CalendarRepository` exposes
/// `today()` but not the instant it is based on (docs/requests/schedule.md §2), so this keeps the
/// system time of day and moves it onto the repository's today. Live repositories derive today
/// from the system clock, so the shift is zero there; the demo environment starts on a fixed day,
/// and this keeps the join window and "today" consistent with it.
public struct RepositoryAlignedClock: WaiveraClock {
    private let calendar: any CalendarRepository

    public init(calendar: any CalendarRepository) {
        self.calendar = calendar
    }

    public var now: Date {
        let real = Date()
        let zone = calendar.scheduleTimeZone().zone
        let repositoryToday = calendar.today()
        let systemToday = CalendarDate(real, in: zone)
        guard repositoryToday != systemToday else { return real }
        let sinceMidnight = real.timeIntervalSince(systemToday.startInstant(in: zone))
        return repositoryToday.startInstant(in: zone).addingTimeInterval(sinceMidnight)
    }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
