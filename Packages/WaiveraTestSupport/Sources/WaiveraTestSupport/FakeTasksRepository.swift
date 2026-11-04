import Foundation
import WaiveraAPI
import WaiveraData

/// Demo casework and own work around the demo day: overdue, delayed, this week and next week
/// rows, with activity, files and a request waiting on review. Every call can be made to fail.
public final class FakeTasksRepository: TasksRepository, @unchecked Sendable {
    public let failure = LockedValue<WaiveraError?>(nil)
    public let logged = LockedValue<[NewActivity]>([])
    private let casework: [TaskSummary]
    private let mine: [TaskSummary]
    private let activityLog = LockedValue<[Int: [TaskActivity]]>([:])

    public init(empty: Bool = false) {
        let today = DemoData.today
        casework = empty ? [] : Self.demoCasework(today: today)
        mine = empty ? [] : Self.demoMine(today: today)
        activityLog.update { $0 = empty ? [:] : [12: Self.demoActivity(now: DemoData.now)] }
    }

    public func tasks(_ query: TaskQuery, page: Int) async throws -> TaskPage {
        try check()
        var rows = query.scope == .casework ? casework : mine
        if query.assignedToMe { rows = rows.filter { $0.assigneeId == DemoData.viewerId } }
        let today = DemoData.today
        switch query.window {
        case .dueSoon: rows = rows.filter { ($0.due ?? today) >= today && ($0.due ?? today) <= today.adding(days: 31) }
        case .overdue: rows = rows.filter { ($0.due ?? today) < today }
        case .allOpen: break
        }
        if query.scope == .casework {
            switch query.delays {
            case .show: break
            case .hide: rows = rows.filter { !$0.delayed }
            case .only: rows = rows.filter(\.delayed)
            }
        }
        let search = query.search.trimmingCharacters(in: .whitespaces).lowercased()
        if !search.isEmpty {
            rows = rows.filter { "\($0.key) \($0.title) \($0.about ?? "")".lowercased().contains(search) }
        }
        let size = APIClient.taskPageSize
        let start = max(0, (page - 1) * size)
        return TaskPage(items: Array(rows.dropFirst(start).prefix(size)), totalCount: rows.count)
    }

    public func counts(scope: TaskScope, assignedToMe: Bool) async throws -> TaskCounts {
        let base = TaskQuery(scope: scope, window: .allOpen, assignedToMe: assignedToMe)
        var late = base
        late.window = .overdue
        late.delays = scope == .casework ? .hide : .show
        var delayed = base
        delayed.delays = .only
        return TaskCounts(
            open: try await tasks(base, page: 1).totalCount,
            overdue: try await tasks(late, page: 1).totalCount,
            delayed: scope == .casework ? try await tasks(delayed, page: 1).totalCount : 0
        )
    }

    public func task(id: Int) async throws -> TaskDetail {
        try check()
        guard let row = (casework + mine).first(where: { $0.id == id }) else { throw WaiveraError.notFound }
        return TaskDetail(
            id: row.id,
            key: row.key,
            title: row.title,
            description: "Review the intake packet with the family and confirm the plan of care before the visit.",
            state: row.state,
            type: casework.contains(row) ? "Intake" : "Training",
            start: row.due?.adding(days: -14),
            due: row.due,
            assignedBy: "Dana Cole",
            about: row.about,
            webPath: "/task/\(row.key)",
            assigneeName: row.assigneeName,
            isClientTask: casework.contains(row),
            delay: row.delayed
                ? TaskDelay(
                    reason: "Hospital stay",
                    explanation: "Back home next week.",
                    start: row.due,
                    through: row.delayedThrough
                )
                : nil
        )
    }

    public func activity(taskId: Int) async throws -> [TaskActivity] {
        try check()
        return activityLog.get()[taskId] ?? []
    }

    public func activityTypes() async throws -> [ActivityType] {
        try check()
        return [
            ActivityType(id: 1, name: "Home visit", recommendedMinutes: nil, fixedDescription: nil),
            ActivityType(id: 2, name: "Phone call", recommendedMinutes: 15, fixedDescription: nil),
            ActivityType(id: 3, name: "Plan review", recommendedMinutes: 30, fixedDescription: "Reviewed the plan"),
        ]
    }

    public func logActivity(_ activity: NewActivity) async throws {
        try check()
        logged.update { $0.append(activity) }
        let types = try await activityTypes()
        activityLog.update { log in
            let row = TaskActivity(
                id: 1000 + (log[activity.taskId]?.count ?? 0),
                type: types.first { $0.id == activity.typeId }?.name ?? "",
                minutes: activity.minutes,
                at: activity.completedAt,
                authorId: DemoData.viewerId,
                authorName: "Alex Rivera",
                description: activity.description
            )
            log[activity.taskId, default: []].append(row)
        }
    }

    public func attachments(taskId: Int) async throws -> [TaskAttachment] {
        try check()
        guard taskId == 12 else { return [] }
        let now = DemoData.now
        return [
            TaskAttachment(
                attachmentId: 41,
                fileId: "f41",
                name: "Care plan 2026.pdf",
                sizeBytes: 182_000,
                addedAt: now.addingTimeInterval(-3_600),
                addedBy: "Dana Cole",
                kind: .pdf
            ),
            TaskAttachment(
                attachmentId: 42,
                fileId: "f42",
                name: "Home photo.png",
                sizeBytes: 640_000,
                addedAt: now.addingTimeInterval(-86_400),
                addedBy: "Alex Rivera",
                kind: .image
            ),
            TaskAttachment(
                attachmentId: 43,
                fileId: "f43",
                name: "Visit notes.txt",
                sizeBytes: 1_200,
                addedAt: now.addingTimeInterval(-172_800),
                addedBy: "Alex Rivera",
                kind: .text
            ),
            TaskAttachment(
                attachmentId: 44,
                fileId: "f44",
                name: "Intake packet.docx",
                sizeBytes: 54_000,
                addedAt: now.addingTimeInterval(-259_200),
                addedBy: "Dana Cole",
                kind: .word
            ),
            TaskAttachment(
                attachmentId: 45,
                fileId: "f45",
                name: "Budget.xlsx",
                sizeBytes: 30_000,
                addedAt: now.addingTimeInterval(-345_600),
                addedBy: "Dana Cole",
                kind: .other
            ),
        ]
    }

    public func fileData(taskId: Int, attachment: TaskAttachment) async throws -> Data {
        try check()
        switch attachment.kind {
        case .text:
            return Data(
                """
                Oct 21 visit

                Jordan was in good spirits. Mom asked to move Thursday's visit to the afternoon.

                Follow-ups:
                - Confirm 2:30 PM with Mom
                - Upload the signed plan
                """.utf8
            )
        default:
            throw WaiveraError.notFound
        }
    }

    private func check() throws {
        if let error = failure.get() { throw error }
    }

    private static func demoCasework(today: CalendarDate) -> [TaskSummary] {
        let me = DemoData.viewerId
        return [
            TaskSummary(
                id: 12,
                key: "HEA-1042",
                title: "Intake review",
                due: today.adding(days: -2),
                state: .inProgress,
                about: "Jordan Lee",
                assigneeId: me,
                assigneeName: "Alex Rivera"
            ),
            TaskSummary(
                id: 14,
                key: "HEA-1047",
                title: "Quarterly visit",
                due: today.adding(days: -5),
                state: .notStarted,
                about: "Sam Ortiz",
                assigneeId: me,
                assigneeName: "Alex Rivera",
                delayed: true,
                delayedThrough: today.adding(days: 6)
            ),
            TaskSummary(
                id: 15,
                key: "HEA-1050",
                title: "Plan of care signature",
                due: today.adding(days: 1),
                state: .inReview,
                about: "Mia Chen",
                assigneeId: "u-dana",
                assigneeName: "Dana Cole",
                pendingClosure: true
            ),
            TaskSummary(
                id: 16,
                key: "HEA-1053",
                title: "Monthly contact",
                due: today.adding(days: 3),
                state: .notStarted,
                about: "Jordan Lee",
                assigneeId: me,
                assigneeName: "Alex Rivera"
            ),
            TaskSummary(
                id: 17,
                key: "HEA-1060",
                title: "Annual reassessment",
                due: today.adding(days: 9),
                state: .notStarted,
                about: "Ava Patel",
                assigneeId: "u-dana",
                assigneeName: "Dana Cole"
            ),
        ]
    }

    private static func demoMine(today: CalendarDate) -> [TaskSummary] {
        [
            TaskSummary(
                id: 31,
                key: "HEA-2001",
                title: "CPR recertification",
                due: today.adding(days: 4),
                state: .notStarted,
                about: "Alex Rivera",
                assigneeId: DemoData.viewerId,
                assigneeName: "Alex Rivera"
            ),
            TaskSummary(
                id: 32,
                key: "HEA-2004",
                title: "HIPAA refresher",
                due: today.adding(days: 12),
                state: .inProgress,
                about: "Alex Rivera",
                assigneeId: DemoData.viewerId,
                assigneeName: "Alex Rivera"
            ),
        ]
    }

    private static func demoActivity(now: Date) -> [TaskActivity] {
        [
            TaskActivity(
                id: 1,
                type: "Phone call",
                minutes: 15,
                at: now.addingTimeInterval(-259_200),
                authorId: "u-dana",
                authorName: "Dana Cole",
                description: "Called Mom to confirm the visit window and the documents she still needs."
            ),
            TaskActivity(
                id: 2,
                type: "Home visit",
                minutes: 60,
                at: now.addingTimeInterval(-86_400),
                authorId: DemoData.viewerId,
                authorName: "Alex Rivera",
                description: "Walked through the intake packet with the family. Jordan wants to ride the "
                    + "bus to the clinic on his own, so we added travel training to the goals."
            ),
        ]
    }
}

/// Demo change requests: one more-time and one delay waiting on review, and the person's own.
public final class FakeRequestsRepository: RequestsRepository, @unchecked Sendable {
    public let failure = LockedValue<WaiveraError?>(nil)
    public let decided = LockedValue<[(Int, Bool)]>([])
    public let asked = LockedValue<[String]>([])
    private let accessCell: StateCell<RequestAccess>
    private let waitingCell: StateCell<[ChangeRequest]?>

    public init(
        access: RequestAccess = RequestAccess(
            canAskMoreTime: true,
            canAskClosure: true,
            showsRequests: true,
            includePendingApprovals: true,
            loaded: true
        ),
        empty: Bool = false
    ) {
        accessCell = StateCell(access)
        waitingCell = StateCell(empty ? [] : Self.demoWaiting())
    }

    public func access() -> AsyncStream<RequestAccess> { accessCell.stream() }
    public func currentAccess() async -> RequestAccess { accessCell.current }
    public func waiting() -> AsyncStream<[ChangeRequest]?> { waitingCell.stream() }
    public func setAccess(_ access: RequestAccess) { accessCell.set(access) }
    public func setWaiting(_ list: [ChangeRequest]?) { waitingCell.set(list) }

    public func refreshAccess() async throws { try check() }
    public func ensureAccess() async {}
    public func refreshWaiting() async throws { try check() }

    public func mine() async throws -> [ChangeRequest] {
        try check()
        let today = DemoData.today
        return [
            ChangeRequest(
                id: 70,
                kind: .moreTime,
                typeName: "Task Extension Request",
                status: .approved,
                requesterId: DemoData.viewerId,
                requesterName: "Alex Rivera",
                approverName: "Dana Cole",
                requestedAt: DemoData.now.addingTimeInterval(-432_000),
                taskId: 16,
                taskTitle: "Monthly contact",
                reason: "Family request",
                currentDue: today.adding(days: -1),
                requestedDue: today.adding(days: 3)
            )
        ]
    }

    public func decide(_ request: ChangeRequest, approve: Bool) async throws {
        let before = waitingCell.current
        waitingCell.update { $0 = $0?.filter { $0.id != request.id } }
        if let error = failure.get() {
            waitingCell.set(before)
            throw error
        }
        decided.update { $0.append((request.id, approve)) }
    }

    public func options(taskId: Int) async throws -> ChangeOptions {
        try check()
        let today = DemoData.today
        return ChangeOptions(
            taskId: taskId,
            currentDue: today.adding(days: -2),
            canAskMoreTime: true,
            delay: DelayPeriod(start: today.adding(days: -2), end: today.adding(days: 12), renewal: false),
            hasPendingRequest: false
        )
    }

    public func moreTimeReasons() async throws -> [ChangeReason] {
        try check()
        return [
            ChangeReason(
                id: 1,
                name: "Family request",
                description: "The family asked to move it.",
                requiresEvidence: false
            ),
            ChangeReason(id: 2, name: "Medical", description: nil, requiresEvidence: true),
        ]
    }

    public func delayReasons() async throws -> [ChangeReason] {
        try check()
        return [ChangeReason(id: 5, name: "Hospital stay", description: nil, requiresEvidence: false)]
    }

    public func closureReasons() async throws -> [ChangeReason] {
        try check()
        return [
            ChangeReason(id: 8, name: "Duplicate task", description: nil, requiresEvidence: false),
            ChangeReason(id: 9, name: "Other", description: nil, requiresEvidence: false, needsComment: true),
        ]
    }

    public func files(taskId: Int) async throws -> [TaskFileRef] {
        try check()
        return [TaskFileRef(attachmentId: 41, name: "Care plan 2026.pdf")]
    }

    public func askMoreTime(
        taskId: Int,
        newDue: CalendarDate,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?
    ) async throws -> RequestOutcome {
        try check()
        asked.update { $0.append("moreTime:\(taskId):\(newDue.isoString):\(reasonId)") }
        return .pending
    }

    public func reportDelay(
        taskId: Int,
        period: DelayPeriod,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?
    ) async throws -> RequestOutcome {
        try check()
        asked.update { $0.append("delay:\(taskId):\(period.end.isoString):\(reasonId)") }
        return .pending
    }

    public func askClosure(taskId: Int, reasonId: Int64, comment: String) async throws {
        try check()
        asked.update { $0.append("closure:\(taskId):\(reasonId)") }
    }

    private func check() throws {
        if let error = failure.get() { throw error }
    }

    private static func demoWaiting() -> [ChangeRequest] {
        let today = DemoData.today
        return [
            ChangeRequest(
                id: 81,
                kind: .moreTime,
                typeName: "Task Extension Request",
                status: .pending,
                requesterId: "u-dana",
                requesterName: "Dana Cole",
                requestedAt: DemoData.now.addingTimeInterval(-7_200),
                taskId: 17,
                taskTitle: "Annual reassessment",
                reason: "Family request",
                explanation: "Mom is traveling until the 20th.",
                currentDue: today.adding(days: 9),
                requestedDue: today.adding(days: 16)
            ),
            ChangeRequest(
                id: 82,
                kind: .delay,
                typeName: "Task Delay Request",
                status: .pending,
                requesterId: "u-sam",
                requesterName: "Sam Brooks",
                requestedAt: DemoData.now.addingTimeInterval(-90_000),
                taskId: 14,
                taskTitle: "Quarterly visit",
                reason: "Hospital stay",
                explanation: "Admitted on Monday.",
                delayStart: today.adding(days: -5),
                delayEnd: today.adding(days: 6)
            ),
        ]
    }
}
