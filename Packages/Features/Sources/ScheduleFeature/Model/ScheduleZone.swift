import Foundation
import WaiveraData

/// Whether the screen names the zone: when it differs from the device's, or when the fallback is
/// in effect (so the person knows their profile has no zone).
public struct ZoneNotice: Sendable, Hashable {
    public let zone: ScheduleZone

    public static func make(zone: ScheduleZone, deviceZone: TimeZone) -> ZoneNotice? {
        guard zone.isFallback || zone.identifier != deviceZone.identifier else { return nil }
        return ZoneNotice(zone: zone)
    }
}
