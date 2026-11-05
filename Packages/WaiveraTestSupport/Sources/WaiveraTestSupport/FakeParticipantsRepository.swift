import Foundation
import WaiveraAPI
import WaiveraData

/// The demo participants behind the casework (Android `DemoParticipantRepository`): a profile
/// for each, their open demo tasks, and knobs for failures and a participant the viewer can't see.
public final class FakeParticipantsRepository: ParticipantsRepository, @unchecked Sendable {
    /// The demo casework's participants by the name About shows.
    public static let demoIds = ["Jordan Lee": 501, "Sam Ortiz": 502, "Mia Chen": 503, "Ava Patel": 504]

    public let failure = LockedValue<WaiveraError?>(nil)
    /// Fails the open tasks only; the profile still loads.
    public let tasksFailure = LockedValue<WaiveraError?>(nil)
    /// Participants outside the viewer's roles.
    public let hidden = LockedValue<Set<Int>>([])
    public let profiles: LockedValue<[Int: ParticipantProfile]>
    public let calls = CallLog()
    private let tasks: FakeTasksRepository

    public init(tasks: FakeTasksRepository) {
        self.tasks = tasks
        profiles = LockedValue(Self.demoProfiles(today: DemoData.today))
    }

    public func profile(id: Int) async throws -> ParticipantProfile {
        calls.record("profile:\(id)")
        if let error = failure.get() { throw error }
        if hidden.get().contains(id) { throw WaiveraError.forbidden }
        guard let profile = profiles.get()[id] else { throw WaiveraError.notFound }
        return profile
    }

    public func openTasks(id: Int) async throws -> [TaskSummary] {
        calls.record("tasks:\(id)")
        if let error = failure.get() ?? tasksFailure.get() { throw error }
        guard let name = profiles.get()[id]?.name else { return [] }
        return tasks.casework(about: name)
            .filter { $0.state != .closed && $0.state != .completed }
            .sorted { lhs, rhs in
                guard let left = lhs.due else { return false }
                guard let right = rhs.due else { return true }
                return left < right
            }
    }

    private static func demoProfiles(today: CalendarDate) -> [Int: ParticipantProfile] {
        let jordan = ParticipantProfile(
            id: 501,
            name: "Jordan Lee",
            initials: "JL",
            waiver: "Community Choices",
            region: "Region 4",
            mobile: "(555) 010-2231",
            email: "jordan.lee@example.com",
            planStart: today.addingMonths(-8),
            planEnd: today.addingMonths(4).adding(days: -1),
            certification: today.addingMonths(-9),
            linkage: today.addingMonths(-20),
            birthDate: CalendarDate(year: 1988, month: 6, day: 2),
            intake: "Transition",
            compliant: true
        )
        let sam = ParticipantProfile(
            id: 502,
            name: "Sam Ortiz",
            initials: "SO",
            waiver: "Supports Waiver",
            mobile: "(555) 010-4410",
            planStart: today.addingMonths(-12).adding(days: -6),
            planEnd: today.adding(days: -6),
            compliant: false,
            changePending: true
        )
        let mia = ParticipantProfile(id: 503, name: "Mia Chen", initials: "MC", planEnd: today.adding(days: 12))
        let ava = ParticipantProfile(id: 504, name: "Ava Patel", initials: "AP", deactivated: true)
        return [501: jordan, 502: sam, 503: mia, 504: ava]
    }
}
