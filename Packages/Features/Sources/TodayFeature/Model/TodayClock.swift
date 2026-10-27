import Foundation
import WaiveraAPI
import WaiveraData

#if DEBUG
    import WaiveraTestSupport
#endif

/// The clock Today measures "now" with. `DataEnvironment` does not expose the data layer's
/// clock (docs/requests/today.md §1), so in DEBUG builds the fake environment is detected and
/// its demo clock used, keeping relative times true to the demo data.
enum TodayClock {
    static func resolve(for environment: DataEnvironment) -> any WaiveraClock {
        #if DEBUG
            if environment.calendar is FakeCalendarRepository { return DemoClock() }
        #endif
        return SystemClock()
    }
}
