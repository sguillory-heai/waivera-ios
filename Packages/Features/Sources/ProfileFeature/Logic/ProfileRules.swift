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

    /// What a time off or files card shows: each loads and fails on its own (08 §2-4).
    public enum Display: Equatable, Sendable {
        case hidden
        case loading
        /// Nothing to show and the section's load failed; the card offers Retry.
        case failed
        case content
    }

    /// Time off hides when the employee has no balances or requests.
    public static func timeOff(_ content: OwnProfile?) -> Display {
        display(phase: content?.sections.timeOff, hasValue: content?.timeOff != nil) {
            TimeOffRules.hasContent(content?.timeOff)
        }
    }

    /// Files always show once loaded; an empty list reads "No files".
    public static func files(_ content: OwnProfile?) -> Display {
        let phase = content?.sections.files
        let hasValue = phase == .loaded || content?.files.isEmpty == false
        return display(phase: phase, hasValue: hasValue) { true }
    }

    private static func display(phase: ResourcePhase?, hasValue: Bool, showsContent: () -> Bool) -> Display {
        guard let phase else { return .hidden }
        if hasValue { return showsContent() ? .content : .hidden }
        switch phase {
        case .failed: return .failed
        case .idle, .loading: return .loading
        case .loaded: return showsContent() ? .content : .hidden
        }
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

    /// The zone the profile shows and dates render in: the profile's saved named zone, else the
    /// session's. When neither is a named zone, America/Chicago (dates.md §2); never the device.
    public static func timeZone(profile: EmployeeProfile?, user: CurrentUser?) -> (zone: TimeZone, isFallback: Bool) {
        if let zone = ScheduleZone.namedZone(profile?.timeZoneIdentifier) { return (zone, false) }
        let zone = user?.scheduleZone ?? ScheduleZone.resolve(savedIdentifier: nil)
        return (zone.timeZone, zone.isFallback)
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
