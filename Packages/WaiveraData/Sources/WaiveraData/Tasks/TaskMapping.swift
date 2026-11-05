import Foundation
import WaiveraAPI

/// Turns the server's task shapes into the phone's. Due and start dates are literal calendar
/// dates: only their `YYYY-MM-DD` part is read, so no zone ever moves a task to another day.
/// Activity times are UTC instants.
enum TaskMapping {
    private static let employeeContext = "employee"
    private static let employeeFile = "employeefile"

    static func summary(_ dto: TaskListResponse) -> TaskSummary {
        let assigned = assignee(dto.assignee, dto.assignees)
        return TaskSummary(
            id: dto.id,
            key: key(dto.organization, dto.friendlyId ?? dto.id),
            title: trimmed(dto.title) ?? "",
            due: date(dto.effectiveEndDate ?? dto.endDate),
            state: TaskState(name: dto.taskStatus?.name),
            about: about(dto.participant, dto.subjectEmployee),
            assigneeId: assigned?.id,
            assigneeName: name(assigned),
            pendingClosure: dto.hasPendingDeletion ?? false,
            delayed: dto.currentTaskDelay != nil,
            delayedThrough: date(dto.currentTaskDelay?.delayEndDate)
        )
    }

    /// The main assignee, as the server picks it: the first assignment that is neither the
    /// reporter nor a co-assignee. Task endpoints send the list, not the single field.
    static func assignee(_ single: TaskUserResponse?, _ list: [TaskAssignmentResponse]?) -> TaskUserResponse? {
        single ?? list?.first { !$0.isReporter && !$0.isCoAssignee }?.user
    }

    static func detail(_ dto: TaskResponse) -> TaskDetail {
        let key = key(dto.organization, dto.friendlyId ?? dto.id)
        let assigneeName = name(assignee(dto.assignee, dto.assignees))
        let pending = (dto.administrativeTransactionRequests ?? [])
            .map(RequestMapping.request)
            .filter { $0.status == .pending }
            .max { ($0.requestedAt ?? .distantPast) < ($1.requestedAt ?? .distantPast) }
        return TaskDetail(
            id: dto.id,
            key: key,
            title: trimmed(dto.title) ?? "",
            description: trimmed(dto.description),
            state: TaskState(name: dto.taskStatus?.name),
            type: trimmed(dto.subType?.name),
            start: date(dto.startDate),
            due: date(dto.effectiveEndDate ?? dto.endDate),
            assignedBy: name(dto.reporter),
            about: about(dto.participant, dto.subjectEmployee),
            participantId: participantId(dto.participant),
            webPath: "/task/\(key)",
            assigneeName: assigneeName,
            isClientTask: dto.taskContext?.trimmingCharacters(in: .whitespaces).lowercased() != employeeContext,
            pendingRequest: pending,
            delay: dto.currentTaskDelay.map(delay),
            review: ReviewMapping.access(dto.capabilities, ready: dto.isTaskReady ?? false),
            steps: ReviewMapping.steps(dto.workflowBlueprint, assignee: assigneeName),
            planDates: ReviewMapping.planDates(dto.participant)
        )
    }

    static func delay(_ dto: TaskDelaySummaryResponse) -> TaskDelay {
        TaskDelay(
            reason: trimmed(dto.reasonName),
            explanation: trimmed(dto.explanation),
            start: date(dto.delayStartDate),
            through: date(dto.delayEndDate)
        )
    }

    /// Oldest first, so new work lands at the bottom as in a conversation. Replies in an
    /// activity's thread and removed activity are not shown.
    static func activity(_ items: [TaskActionResponse]) -> [TaskActivity] {
        items
            .filter { $0.deleted != true && $0.parentTaskActionId == nil }
            .map { dto in
                TaskActivity(
                    id: dto.id,
                    type: dto.actionSubType?.actionSubTypeName.map(readable) ?? "",
                    minutes: max(0, dto.durationInMinutes ?? 0),
                    at: instant(dto.completionTime) ?? instant(dto.createDate),
                    authorId: dto.author?.id,
                    authorName: name(dto.author),
                    description: trimmed(dto.description)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.at, rhs.at) {
                case (nil, nil): lhs.id < rhs.id
                case (nil, _): true
                case (_, nil): false
                case (let left?, let right?): left == right ? lhs.id < rhs.id : left < right
                }
            }
    }

    /// Files with no id or one an employee-file deletion removed are left out; newest first.
    static func attachments(_ items: [TaskAttachmentResponse]) -> [TaskAttachment] {
        items
            .filter { $0.employeeFileDeleted != true }
            .compactMap { dto -> TaskAttachment? in
                guard let file = dto.file, let fileId = trimmed(file.id) else { return nil }
                let name = trimmed(file.fileName) ?? fileId
                return TaskAttachment(
                    attachmentId: dto.id,
                    fileId: fileId,
                    name: name,
                    sizeBytes: max(0, file.size ?? 0),
                    addedAt: instant(file.createDate),
                    addedBy: self.name(file.author),
                    employeeFile: dto.fileStorageKind?.lowercased() == employeeFile,
                    kind: FileKind(name: name, mimeType: file.mimeType)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.addedAt, rhs.addedAt) {
                case (nil, nil): lhs.attachmentId > rhs.attachmentId
                case (nil, _): false
                case (_, nil): true
                case (let left?, let right?): left == right ? lhs.attachmentId > rhs.attachmentId : left > right
                }
            }
    }

    /// The types a person can log. One that needs a file names a template by id (sprout_web
    /// `LogActivityModal`); a template the organization no longer has leaves the file under its own name.
    static func activityTypes(
        _ items: [ActionSubTypeResponse],
        templates: [TemplateFileResponse] = []
    ) -> [ActivityType] {
        items
            .compactMap { dto -> ActivityType? in
                guard dto.isUserLoggable == true, let id = dto.id, let name = trimmed(dto.actionSubTypeName)
                else { return nil }
                let minutes = dto.recommendedTimeInMinutes.flatMap { $0 > 0 ? $0 : nil }
                let templateId = dto.requiresFile.flatMap { $0 > 0 ? $0 : nil }
                let template = templateId.flatMap { id in templates.first { $0.id == id } }
                return ActivityType(
                    id: id,
                    name: readable(name),
                    recommendedMinutes: minutes,
                    fixedDescription: trimmed(dto.description),
                    needsFile: templateId != nil,
                    fileTemplate: template.flatMap(UploadMapping.template)
                )
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// `HEA-1042` as the web labels it; just the number when the agency has no abbreviation.
    static func key(_ organization: TaskOrganizationResponse?, _ friendlyId: Int) -> String {
        guard let abbreviation = trimmed(organization?.abbreviation) else { return String(friendlyId) }
        return "\(abbreviation)-\(friendlyId)"
    }

    static func name(_ user: TaskUserResponse?) -> String? {
        guard let user else { return nil }
        if let display = trimmed(user.displayName) { return display }
        let joined = [trimmed(user.firstName), trimmed(user.lastName)].compactMap(\.self).joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private static func about(_ participant: TaskParticipantResponse?, _ employee: TaskUserResponse?) -> String? {
        participantName(participant) ?? name(employee)
    }

    /// Only when About names the participant; a nameless one falls back to the employee's name.
    private static func participantId(_ participant: TaskParticipantResponse?) -> Int? {
        guard let id = participant?.id, id > 0, participantName(participant) != nil else { return nil }
        return id
    }

    private static func participantName(_ participant: TaskParticipantResponse?) -> String? {
        let joined = [trimmed(participant?.firstName), trimmed(participant?.lastName)]
            .compactMap(\.self)
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// Some system types are stored in capitals (`PHONE CALL`); people read them in sentence case.
    static func readable(_ name: String) -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: \.isLowercase), let first = value.first else { return value }
        return first.uppercased() + value.dropFirst().lowercased()
    }

    static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func date(_ raw: String?) -> CalendarDate? { raw.flatMap(CalendarDate.init(parsing:)) }

    static func instant(_ raw: String?) -> Date? { raw.flatMap(WaiveraInstant.parse) }
}
