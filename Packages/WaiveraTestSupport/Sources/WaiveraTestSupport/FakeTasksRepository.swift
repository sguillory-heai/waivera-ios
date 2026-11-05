import Foundation
import WaiveraAPI
import WaiveraData

/// Demo casework and own work around the demo day: overdue, delayed, this week and next week
/// rows, with activity, files and a request waiting on review. Every call can be made to fail.
public final class FakeTasksRepository: TasksRepository, @unchecked Sendable {
    public let failure = LockedValue<WaiveraError?>(nil)
    public let logged = LockedValue<[NewActivity]>([])
    /// Every read, as "task:12", "activity:12" or "files:12".
    public let calls = CallLog()
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

    /// The demo casework about one participant, for their profile.
    func casework(about name: String) -> [TaskSummary] { casework.filter { $0.about == name } }

    public func task(id: Int) async throws -> TaskDetail {
        calls.record("task:\(id)")
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
            participantId: casework.contains(row) ? row.about.flatMap { FakeParticipantsRepository.demoIds[$0] } : nil,
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
                : nil,
            review: Self.demoReview[row.id] ?? .none,
            steps: Self.demoReview[row.id] == nil ? [] : Self.demoSteps(active: row.id == 15 ? 2 : 1),
            planDates: casework.contains(row) ? PlanDates(start: row.due?.adding(days: -300), end: row.due) : nil
        )
    }

    /// Submit on the assignee's tasks (one still waiting on a form), Approve, Approve all and
    /// Reject on the one in review.
    static let demoReview: [Int: TaskReviewAccess] = [
        12: TaskReviewAccess(canSubmit: true, ready: true),
        16: TaskReviewAccess(canSubmit: true, ready: false),
        15: TaskReviewAccess(canApprove: true, canApproveAll: true, remainingStages: 2, canReject: true, ready: true),
    ]

    /// Assignee, supervisor and director stages; `active` (from 1) is the one the task waits on.
    static func demoSteps(active: Int) -> [WorkflowStep] {
        ["Assignee", "Supervisor", "Director"].enumerated().map { index, role in
            let order = index + 1
            let status: StepStatus = order < active ? .completed : (order == active ? .active : .future)
            return WorkflowStep(
                order: order,
                role: role,
                status: status,
                approverName: order < active ? "Priya Raman" : nil,
                waitingOn: order == active ? "Jordan Ellis" : nil
            )
        }
    }

    public func activity(taskId: Int) async throws -> [TaskActivity] {
        calls.record("activity:\(taskId)")
        try check()
        return activityLog.get()[taskId] ?? []
    }

    public func activityTypes() async throws -> [ActivityType] {
        try check()
        return [
            ActivityType(id: 1, name: "Home visit", recommendedMinutes: nil, fixedDescription: nil),
            ActivityType(id: 2, name: "Phone call", recommendedMinutes: 15, fixedDescription: nil),
            ActivityType(id: 3, name: "Plan review", recommendedMinutes: 30, fixedDescription: "Reviewed the plan"),
            ActivityType(
                id: 4,
                name: "Signed plan received",
                recommendedMinutes: 10,
                fixedDescription: nil,
                needsFile: true,
                fileTemplate: FileTemplate(id: 7, name: "Signed plan", typeId: 4, categoryId: nil)
            ),
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

    public func fileExport(taskId: Int, attachment: TaskAttachment) async throws -> Data {
        calls.record("fileExport:\(taskId):\(attachment.attachmentId)")
        return try await fileData(taskId: taskId, attachment: attachment)
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
        case .word:
            return Data(base64Encoded: DemoFiles.intakePacket) ?? Data()
        case .pdf:
            return Data(DemoFiles.carePlan.utf8)
        case .image:
            return Data(base64Encoded: DemoFiles.homePhoto) ?? Data()
        case .other:
            throw WaiveraError.notFound
        }
    }

    /// The task whose key ends in `number` ("HEA-1042" for 1042), as `api/tasks/lookup` finds it.
    public func lookup(number: Int) async throws -> TaskDetail {
        try check()
        guard let row = (casework + mine).first(where: { $0.key.hasSuffix("-\(number)") }) else {
            throw WaiveraError.notFound
        }
        return try await task(id: row.id)
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

    public func leaveBalance(employeeId: String, leaveTypeId: Int) async throws -> LeaveBalance? {
        try check()
        return LeaveBalance(leaveTypeId: leaveTypeId, tracksBalance: true, availableMinutes: 2_400)
    }

    public func leaveZone() async -> TimeZone? { TimeZone(identifier: "America/Chicago") }

    public func trainingCredit(requestId: Int) async throws -> TrainingCredit {
        try check()
        return TrainingCredit(
            requestId: requestId,
            course: "CPR and First Aid",
            employeeName: "Jordan Lee",
            trainer: "Pat Morgan",
            provider: "Red Cross",
            completed: DemoData.today.adding(days: -6),
            hours: 4,
            pending: true,
            revision: 3,
            canApprove: true,
            needsApproveReason: false,
            uploadedBy: nil,
            blocked: nil,
            reviewOnWeb: false
        )
    }

    public func trainingCertificate(requestId: Int) async throws -> DownloadedFile {
        try check()
        return DownloadedFile(data: Data("%PDF-1.4\n".utf8), name: "Certificate.pdf", mimeType: "application/pdf")
    }

    public let leaveSends = LockedValue<[LeaveDraft]>([])
    public let leaveRefusal = LockedValue<LeaveSendProblem?>(nil)
    /// What the next preview answers; demo dates otherwise take 8 hours a day from 40.
    public let nextPreview = LockedValue<LeavePreview?>(nil)

    public func leaveTypes() async throws -> [LeaveType] {
        try check()
        return [
            LeaveType(id: 1, name: "Vacation", tracksBalance: true, availableMinutes: 2_400),
            LeaveType(id: 2, name: "Sick leave", tracksBalance: true, availableMinutes: 600),
            LeaveType(id: 3, name: "Unpaid leave", tracksBalance: false, availableMinutes: nil),
        ]
    }

    public func previewLeave(_ draft: LeaveDraft) async throws -> LeavePreview {
        try check()
        if let preview = nextPreview.get() { return preview }
        let minutes = draft.partialDay ? Int(draft.end.timeIntervalSince(draft.start) / 60) : 480
        return LeavePreview(
            requestedMinutes: minutes,
            tracksBalance: true,
            beforeMinutes: 2_400,
            afterMinutes: 2_400 - minutes,
            block: nil,
            impact: LeaveImpact(dueBefore: 0, dueDuring: 1, shortNotice: false)
        )
    }

    public func requestTimeOff(_ draft: LeaveDraft) async throws {
        try check()
        if let problem = leaveRefusal.get() { throw LeaveSendError(problem: problem) }
        leaveSends.update { $0.append(draft) }
    }

    public func decide(_ request: ChangeRequest, approve: Bool, training: TrainingDecision?) async throws {
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

    /// Time off, a profile change and a training credit, for the review sheet's previews and tests.
    public static func demoApprovals() -> [ChangeRequest] {
        let today = DemoData.today
        return [
            ChangeRequest(
                id: 83,
                kind: .timeOff,
                typeName: "Time-Off Request",
                status: .pending,
                requesterId: "u-jordan",
                requesterName: "Jordan Lee",
                requestedAt: DemoData.now.addingTimeInterval(-20_000),
                timeOff: TimeOffReview(
                    leaveType: "Vacation",
                    leaveTypeId: 2,
                    partialDay: false,
                    startDate: today.adding(days: 8),
                    endDate: today.adding(days: 10),
                    start: nil,
                    end: nil,
                    minutes: 1_440,
                    note: "Family trip.",
                    impact: LeaveImpact(dueBefore: 1, dueDuring: 2, shortNotice: true),
                    impactChanged: false,
                    acknowledged: true
                )
            ),
            ChangeRequest(
                id: 84,
                kind: .profileChange,
                typeName: "Profile Change Request",
                status: .pending,
                requesterId: "u-dana",
                requesterName: "Dana Cole",
                requestedAt: DemoData.now.addingTimeInterval(-40_000),
                profile: [
                    ProfileField(field: .mobile, previous: "(555) 010-2299", requested: "(555) 010-7781", changed: true),
                    ProfileField(field: .firstName, previous: "Maya", requested: "Maya", changed: false),
                    ProfileField(field: .lastName, previous: "Ortiz", requested: "Ortiz", changed: false),
                ]
            ),
            ChangeRequest(
                id: 85,
                kind: .trainingCredit,
                typeName: "External Training Credit",
                status: .pending,
                requesterId: "u-jordan",
                requesterName: "Jordan Lee",
                requestedAt: DemoData.now.addingTimeInterval(-60_000)
            ),
        ]
    }
}

/// Small real files for the viewer's previews and tests: a one-page PDF, a 4×3 PNG and a .docx
/// with a title, a heading, a link, a list item, field codes, deleted text and a line break.
public enum DemoFiles {
    public static let carePlan = """
        %PDF-1.4
        1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
        2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
        3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
        4 0 obj<</Length 44>>stream
        BT /F1 24 Tf 72 700 Td (Care plan 2026) Tj ET
        endstream endobj
        5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
        trailer<</Root 1 0 R>>
        %%EOF
        """

    public static let homePhoto =
        "iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGOoCz8ERww4OQBxDBMVEBoxwgAAAABJRU5ErkJggg=="

    public static let intakePacket = """
        UEsDBBQAAAAIAGlmZF3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgAaWZkXbOs
        lFVwAQAAPAMAABEAAAB3b3JkL2RvY3VtZW50LnhtbIVSTU/DMAy98yui3Fm6HRCq1k4cgA0BmkQR56wxa9Q0qRK3Xf896cdgG9N2
        aWv7+dnv1fPFrlCkBuuk0RGdTgJKQKdGSL2N6GfydHtPiUOuBVdGQ0RbcHQR38ybUJi0KkAj8QzahU1EM8QyZMylGRTcTUwJ2te+
        jS04+tBuWWOsKK1JwTk/oFBsFgR3rOBS09hTboxoe+6yi8q17V8f2CogTVhzFdFEogLK4jn7BfQPjFcaeQ6k5GkO2JWxB9kBeoV2
        CbyTPDvLvDSVg8wocYF1gHZehM6v4J0qLTiwNdD4xavmmihZgyONxIy8mYIckTVh1pZgldT5wWCOBDMg78b6nqzb4nSDc12T6+J1
        VQwfUtVq70HQie9rK7HPTUdDxoZ/1nwB5KoltXQSTwQNCL5hAzLJKusEb901E6V2aBPYYbx+eH7sEH+ZY3IBqs9u/WV2lX184QfF
        r1IDGfHY35xlBxVszLn92Hib/ZTx7uMfUEsBAhQDFAAAAAgAaWZkXcccFzwKAAAACAAAABMAAAAAAAAAAAAAAIABAAAAAFtDb250
        ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACABpZmRds6yUVXABAAA8AwAAEQAAAAAAAAAAAAAAgAE7AAAAd29yZC9kb2N1bWVudC54
        bWxQSwUGAAAAAAIAAgCAAAAA2gEAAAAA
        """
        .replacingOccurrences(of: "\n", with: "")
}
