import Foundation
import WaiveraAPI

/// A participant as the web's Participant Profile tab shows them, read only. Dates are calendar
/// days, never shifted by a zone. `changePending` is the viewer's own profile change waiting on
/// approval, as the web's "Update Pending Approval".
public struct ParticipantProfile: Sendable, Hashable {
    public var id: Int
    public var name: String
    public var initials: String
    public var waiver: String?
    public var region: String?
    public var mobile: String?
    public var email: String?
    public var planStart: CalendarDate?
    public var planEnd: CalendarDate?
    public var certification: CalendarDate?
    public var linkage: CalendarDate?
    public var birthDate: CalendarDate?
    public var intake: String?
    public var deactivated: Bool
    public var compliant: Bool
    public var changePending: Bool

    public init(
        id: Int,
        name: String,
        initials: String,
        waiver: String? = nil,
        region: String? = nil,
        mobile: String? = nil,
        email: String? = nil,
        planStart: CalendarDate? = nil,
        planEnd: CalendarDate? = nil,
        certification: CalendarDate? = nil,
        linkage: CalendarDate? = nil,
        birthDate: CalendarDate? = nil,
        intake: String? = nil,
        deactivated: Bool = false,
        compliant: Bool = false,
        changePending: Bool = false
    ) {
        self.id = id
        self.name = name
        self.initials = initials
        self.waiver = waiver
        self.region = region
        self.mobile = mobile
        self.email = email
        self.planStart = planStart
        self.planEnd = planEnd
        self.certification = certification
        self.linkage = linkage
        self.birthDate = birthDate
        self.intake = intake
        self.deactivated = deactivated
        self.compliant = compliant
        self.changePending = changePending
    }
}

/// The read-only participant profile and the participant's open tasks (Android
/// `ParticipantRepository`).
public protocol ParticipantsRepository: Sendable {
    /// Fails with `WaiveraError.forbidden` when the viewer may not see this participant.
    func profile(id: Int) async throws -> ParticipantProfile
    /// Open tasks about the participant that the viewer can see, earliest due first (undated last).
    func openTasks(id: Int) async throws -> [TaskSummary]
}

public struct LiveParticipantsRepository: ParticipantsRepository {
    static let maxPages = 10

    private let api: APIClient
    private let context: SessionContext

    public init(api: APIClient, context: SessionContext) {
        self.api = api
        self.context = context
    }

    public func profile(id: Int) async throws -> ParticipantProfile {
        async let pending = changePending(id)
        let info = try await api.participant(id: id)
        return ParticipantMapping.profile(info, changePending: await pending)
    }

    /// The pending flag is a nicety: the profile still shows when that check fails.
    private func changePending(_ id: Int) async -> Bool {
        guard let me = context.currentUser?.id else { return false }
        return (try? await api.participantChangePending(userId: me, participantId: id)) ?? false
    }

    public func openTasks(id: Int) async throws -> [TaskSummary] {
        // Pages come latest due first, so stopping at page one would drop the most overdue tasks.
        var all: [TaskSummary] = []
        var page = 1
        while page <= Self.maxPages {
            let result = try await api.participantTasks(id: id, page: page)
            all += result.items.map(TaskMapping.summary)
            page += 1
            if result.items.isEmpty || all.count >= result.totalCount { break }
        }
        return ParticipantMapping.open(all)
    }
}

public struct EmptyParticipantsRepository: ParticipantsRepository {
    public init() {}

    public func profile(id: Int) async throws -> ParticipantProfile { throw WaiveraError.notFound }
    public func openTasks(id: Int) async throws -> [TaskSummary] { [] }
}

/// sprout_api `ParticipantInfoResponse` in the phone's terms.
enum ParticipantMapping {
    static func profile(_ dto: ParticipantInfoResponse, changePending: Bool) -> ParticipantProfile {
        let parts = [TaskMapping.trimmed(dto.firstName), TaskMapping.trimmed(dto.lastName)].compactMap(\.self)
        return ParticipantProfile(
            id: dto.id ?? 0,
            name: parts.joined(separator: " "),
            initials: parts.compactMap(\.first).map { String($0).uppercased() }.joined(),
            waiver: TaskMapping.trimmed(dto.waiver?.waiverName) ?? TaskMapping.trimmed(dto.waiver?.code),
            region: TaskMapping.trimmed(dto.region?.regionName),
            mobile: TaskMapping.trimmed(dto.mobileNumber),
            email: TaskMapping.trimmed(dto.email),
            planStart: TaskMapping.date(dto.cpocDate),
            planEnd: TaskMapping.date(dto.cpocEndDate),
            certification: TaskMapping.date(dto.certificationDate),
            linkage: TaskMapping.date(dto.linkageDate),
            birthDate: TaskMapping.date(dto.dateOfBirth),
            intake: TaskMapping.trimmed(dto.intakeType),
            deactivated: dto.deactivated ?? false,
            compliant: dto.isCompliant ?? false,
            changePending: changePending
        )
    }

    /// The server still returns closed tasks; they are not open. Earliest due first, undated last.
    static func open(_ tasks: [TaskSummary]) -> [TaskSummary] {
        tasks
            .filter { $0.state != .closed && $0.state != .completed }
            .enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.due, rhs.element.due) {
                case (let left?, let right?) where left != right: left < right
                case (nil, _?): false
                case (_?, nil): true
                default: lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}
