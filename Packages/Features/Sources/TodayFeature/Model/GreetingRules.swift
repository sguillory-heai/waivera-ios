import Foundation
import WaiveraAPI

/// The part of the day the greeting names.
enum DayPart: Hashable, Sendable {
    case morning, afternoon, evening
}

/// "Good morning, Alex": the part of the day in the employee's zone and their first name, if known.
struct Greeting: Hashable, Sendable {
    var part: DayPart
    var firstName: String?
}

/// Today's greeting. The hour comes from the employee's saved zone, never the device's, so a
/// person whose phone is set elsewhere is still greeted for the time where they work. A named
/// zone keeps the boundaries right across daylight-saving changes.
enum GreetingRules {
    /// Morning starts at 05:00, afternoon at 12:00 and evening at 17:00; the night stays evening.
    static let morningStarts = 5
    static let afternoonStarts = 12
    static let eveningStarts = 17

    static func dayPart(_ now: Date, zone: TimeZone) -> DayPart {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: now)
        switch hour {
        case ..<morningStarts: return .evening
        case ..<afternoonStarts: return .morning
        case ..<eveningStarts: return .afternoon
        default: return .evening
        }
    }

    /// The name to greet by: the first name when the profile has one, else the first word of the
    /// display name. `nil` (a greeting without a name) when neither is usable; never the email.
    static func firstName(_ firstName: String?, displayName: String?) -> String? {
        if let first = firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty { return first }
        let words = displayName?.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) ?? []
        return words.first.map(String.init)
    }

    static func greeting(_ now: Date, zone: TimeZone, firstName: String?) -> Greeting {
        Greeting(part: dayPart(now, zone: zone), firstName: firstName)
    }
}

/// The hero ring: `handled` today and `open` still needing the person.
struct TodayProgress: Hashable, Sendable {
    var handled: Int
    var open: Int

    var total: Int { handled + open }
}

/// The hero's stat tiles. Each is `nil` while its source is still loading (the tile shows a
/// dash), never a guess. Events skip invitations not yet answered and ones the person declined,
/// as Up next does; the week is the employee's Sunday-to-Saturday week in their saved zone.
struct TodayStats: Hashable, Sendable {
    var eventsToday: Int?
    var unreadChats: Int?
    var eventsThisWeek: Int?
}

/// The reward hero's confetti plays once per day in the employee's zone, remembered across
/// launches, so a relaunch or a return to the tab the same day stays still.
enum RewardBurst {
    static let storageKey = "waivera.today.rewardBurstDay"

    /// Whether the burst plays now: it has not played yet on `today` (an ISO date).
    static func plays(today: String, lastPlayed: String) -> Bool {
        !today.isEmpty && today != lastPlayed
    }

    /// A seed per day, so each day's burst is its own but a snapshot of one day is stable.
    static func seed(_ day: CalendarDate?) -> UInt64 {
        UInt64(max(0, day?.daysSinceEpoch ?? 0))
    }
}
