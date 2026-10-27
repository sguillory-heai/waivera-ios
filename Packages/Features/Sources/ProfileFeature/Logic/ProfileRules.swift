import Foundation
import WaiveraAPI
import WaiveraData

/// Which block a list screen shows.
public enum ListPhase: Equatable, Sendable {
    /// First load with nothing cached: the skeleton (after the ~300 ms delay).
    case loading
    /// First load failed with nothing cached: the error card with Try again.
    case failed(WaiveraError)
    /// Loaded and nothing there at all.
    case empty
    /// There is data, but the search hides all of it.
    case noMatches
    case content
}

/// Time-off rules from 08 §3. The API's first row doubles as the summary; `TimeOffOverview`
/// already carries the summary fields separately, so rows here are the request list only.
public enum TimeOffRules {
    /// The profile lists this many requests and says how many more exist.
    public static let visibleRequests = 3

    /// The card is omitted entirely when the response was empty.
    public static func hasContent(_ overview: TimeOffOverview?) -> Bool {
        guard let overview else { return false }
        return !overview.entries.isEmpty
    }

    public static func visibleEntries(_ overview: TimeOffOverview) -> [TimeOffEntry] {
        Array(overview.entries.prefix(visibleRequests))
    }

    public static func hiddenCount(_ overview: TimeOffOverview) -> Int {
        max(0, overview.entries.count - visibleRequests)
    }

    /// Width of the progress fill as 0...1: the remaining share, `100 - clamp(used, 0, 100)`.
    public static func remainingFraction(_ overview: TimeOffOverview) -> Double {
        min(max(overview.remainingPercentage, 0), 100) / 100
    }

    public enum Tone: Equatable, Sendable {
        case warning, danger, success
    }

    public static func tone(_ status: TimeOffEntry.Status) -> Tone {
        switch status {
        case .cancellationPending, .pending: .warning
        case .rejected: .danger
        case .approved: .success
        }
    }
}

/// Section limits on the profile screen (08 §4).
public enum ProfileSections {
    /// The profile shows at most this many employee files.
    public static let visibleFileCount = 5

    public static func visibleFiles(_ files: [EmployeeFile]) -> [EmployeeFile] {
        Array(files.prefix(visibleFileCount))
    }
}

/// Names and identity lines shared by the profile screens.
public enum ProfileText {
    /// Display name, else "First Last", else the session's name, else the email.
    public static func displayName(profile: EmployeeProfile?, user: CurrentUser?) -> String? {
        if let name = profile?.displayName?.nonBlank { return name }
        let parts = [profile?.firstName, profile?.lastName].compactMap { $0?.nonBlank }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return user?.asChatUser.fullName
    }

    public static func displayName(person: PersonProfile?, fallback: String?) -> String? {
        if let person {
            if let name = person.displayName?.nonBlank { return name }
            let parts = [person.firstName, person.lastName].compactMap { $0?.nonBlank }
            if !parts.isEmpty { return parts.joined(separator: " ") }
        }
        return fallback?.nonBlank ?? person?.email?.nonBlank
    }

    /// The first position doubles as the job title under the name.
    public static func jobTitle(_ profile: EmployeeProfile?) -> String? {
        profile?.positions.first?.nonBlank
    }

    /// A list row's value: `nil` (the screen shows "—") when the list is empty.
    public static func joined(_ values: [String]) -> String? {
        let cleaned = values.compactMap(\.nonBlank)
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
    }

    /// The zone the profile shows and dates render in: the profile's saved zone, else the
    /// session's saved zone. The device zone is used only when neither is set or valid.
    public static func timeZone(profile: EmployeeProfile?, user: CurrentUser?) -> (zone: TimeZone, isDevice: Bool) {
        if let zone = profile?.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) { return (zone, false) }
        if let user, !user.isUsingDeviceTimeZone { return (user.scheduleTimeZone, false) }
        return (.current, true)
    }
}

/// Turns hub status updates into "resync now" moments: a connect with a newer epoch than the
/// first one seen. The first status only sets the baseline (05 §1).
struct ReconnectDetector: Sendable {
    private var baseline: Int?

    mutating func isReconnect(_ status: RealtimeStatusSnapshot) -> Bool {
        guard let baseline else {
            self.baseline = status.epoch
            return false
        }
        guard status.isConnected, status.epoch > baseline else { return false }
        self.baseline = status.epoch
        return true
    }
}

/// Runs `action` on every reconnect until the calling task is cancelled.
@MainActor
func onReconnect(_ realtime: any RealtimeStatusRepository, _ action: @MainActor () async -> Void) async {
    var detector = ReconnectDetector()
    for await status in realtime.statuses() {
        if detector.isReconnect(RealtimeStatusSnapshot(isConnected: status.isConnected, epoch: status.epoch)) {
            await action()
        }
    }
}

/// The two fields of `RealtimeStatus` the detector reads, so this file needs no realtime import.
struct RealtimeStatusSnapshot: Sendable {
    var isConnected: Bool
    var epoch: Int
}

extension String {
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
