import Foundation

/// The zone every schedule date is placed in and formatted in: the employee's saved IANA zone,
/// or `America/Chicago` when the profile has none or an unusable one (dates.md §2,
/// `sprout_api/docs/timezone-standard.md`). The device zone is never used for placement.
public struct ScheduleZone: Sendable, Hashable {
    public static let fallbackIdentifier = "America/Chicago"

    public let timeZone: TimeZone
    /// True when the saved zone was missing or invalid and the documented fallback is in effect.
    public let isFallback: Bool

    public init(timeZone: TimeZone, isFallback: Bool) {
        self.timeZone = timeZone
        self.isFallback = isFallback
    }

    public var identifier: String { timeZone.identifier }

    /// Resolves the saved identifier. Fixed offsets ("GMT-6", "+05:00") and abbreviations ("CST")
    /// are rejected: only named zones keep the DST rules the schedule depends on.
    public static func resolve(savedIdentifier: String?) -> ScheduleZone {
        if let zone = namedZone(savedIdentifier) {
            return ScheduleZone(timeZone: zone, isFallback: false)
        }
        return ScheduleZone(timeZone: fallbackTimeZone, isFallback: true)
    }

    public static var fallbackTimeZone: TimeZone {
        // The identifier is a constant IANA name, so the `.current` branch is unreachable.
        TimeZone(identifier: fallbackIdentifier) ?? .current
    }

    /// A named IANA zone (`Region/City`, or `UTC`), else `nil`.
    public static func namedZone(_ raw: String?) -> TimeZone? {
        guard let identifier = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty,
            identifier.contains("/") || identifier == "UTC",
            !identifier.hasPrefix("Etc/GMT"),
            let zone = TimeZone(identifier: identifier)
        else { return nil }
        return zone
    }
}
