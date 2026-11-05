import Foundation
import WaiveraAPI

/// The task review contract (sprout_api workflow, late justification and employee closure) in
/// the phone's terms (Android `ReviewMapping`).
enum ReviewMapping {
    static let blocked = "TASK_COMPLETION_BLOCKED"
    static let warning = "TASK_COMPLETION_WARNING_REQUIRED"
    static let changed = "WORKFLOW_REQUIREMENTS_CHANGED"
    static let notSatisfied = "WORKFLOW_REQUIREMENTS_NOT_SATISFIED"
    static let merge = "CloseAndMergePdfs"
    static let close = "CloseTask"
    static let agree = "Agree"
    static let returnDecision = "ReturnForClarification"

    static func access(_ dto: TaskCapabilitiesResponse?, ready: Bool) -> TaskReviewAccess {
        guard let dto else { return .none }
        return TaskReviewAccess(
            canSubmit: dto.canSubmit ?? false,
            canApprove: dto.canApprove ?? false,
            canApproveAll: dto.canApproveAllRemaining ?? false,
            remainingStages: dto.remainingApprovalStageCount ?? 0,
            canReject: dto.canReject ?? false,
            ready: ready
        )
    }

    /// The server's role for a stage with no role on a client task: the task's own case worker.
    static let caseWorkerRole = "[CASE_WORKER]"

    /// `assignee` is the task's main assignee: a stage with no role goes to them (sprout_api
    /// `TaskService` waterfall), so the note can name them even before the server assigns it.
    static func steps(_ items: [WorkflowStepResponse]?, assignee: String? = nil) -> [WorkflowStep] {
        (items ?? [])
            .sorted { ($0.stepOrder ?? 0) < ($1.stepOrder ?? 0) }
            .map { item in
                let status: StepStatus =
                    switch item.status?.uppercased() {
                    case "COMPLETED": .completed
                    case "ACTIVE": .active
                    case "FUTURE": .future
                    default: .unknown
                    }
                let role = TaskMapping.trimmed(item.stepRole)
                // A pool's person is only the server's first pick among many, so the role reads truer.
                let projected =
                    item.projectedApprover?.isPool == true ? nil : TaskMapping.name(item.projectedApprover?.exactUser)
                return WorkflowStep(
                    order: item.stepOrder ?? 0,
                    role: humanRole(role),
                    status: status,
                    approverName: TaskMapping.name(item.actualApprover),
                    waitingOn: status == .completed ? nil : projected ?? (role == caseWorkerRole ? assignee : nil)
                )
            }
    }

    /// `[CASE_WORKER]` reads "Case worker"; agency role names ("Supervisor") stay as they are.
    static func humanRole(_ role: String?) -> String? {
        guard let role else { return nil }
        guard role.hasPrefix("["), role.hasSuffix("]") else { return role }
        let words = role.dropFirst().dropLast().replacingOccurrences(of: "_", with: " ").lowercased()
        guard let first = words.first else { return nil }
        return first.uppercased() + words.dropFirst()
    }

    static func planDates(_ participant: TaskParticipantResponse?) -> PlanDates? {
        participant.map { PlanDates(start: TaskMapping.date($0.cpocDate), end: TaskMapping.date($0.cpocEndDate)) }
    }

    static func plan(_ dto: ApprovalRequirementsResponse, asked: ApprovalMode) -> ApprovalPlan {
        let mode = [ApprovalMode.currentStage, .allRemaining].first {
            $0.rawValue.caseInsensitiveCompare(dto.approvalMode ?? "") == .orderedSame
        }
        return ApprovalPlan(
            mode: mode ?? asked,
            willComplete: dto.willCompleteTask ?? false,
            previousFiling: TaskMapping.date(dto.previousDriveFilingDate),
            requirementsVersion: dto.requirementsVersion,
            workflowVersion: dto.workflowVersion,
            canApproveAll: dto.canApproveAllRemaining ?? false,
            remainingStages: dto.remainingStageCount ?? 0,
            requirements: requirements(dto.requirements ?? [])
        )
    }

    static func requirements(_ items: [WorkflowRequirementResponse]) -> [StageRequirement] {
        items.map { item in
            StageRequirement(
                actionId: item.actionId ?? 0,
                key: item.requirementKey ?? "",
                actionType: item.actionType ?? "",
                title: TaskMapping.trimmed(item.title) ?? "",
                description: TaskMapping.trimmed(item.description),
                fields: (item.fields ?? []).map(field)
            )
        }
    }

    private static func field(_ dto: WorkflowFieldResponse) -> RequirementField {
        let type: RequirementFieldType =
            switch dto.fieldType?.lowercased() {
            case "date": .date
            case "text": .text
            case "textarea": .longText
            case "number": .number
            default: .unsupported
            }
        let key = dto.key ?? ""
        return RequirementField(
            key: key,
            label: TaskMapping.trimmed(dto.label) ?? key,
            type: type,
            required: dto.required ?? false,
            defaultValue: dto.defaultValue
        )
    }

    /// sprout_web `continueWorkflowApproval`'s request; the server checks both versions.
    static func body(_ send: ApprovalSend) -> ApproveTaskStageBody {
        let answers = send.plan.requirements.compactMap { requirement -> RequirementAnswerBody? in
            guard let values = send.answers[requirement.actionId] else { return nil }
            return RequirementAnswerBody(
                actionId: requirement.actionId,
                requirementKey: requirement.key,
                values: values.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            )
        }
        return ApproveTaskStageBody(
            mode: send.plan.mode.rawValue,
            expectedWorkflowVersion: send.plan.workflowVersion,
            idempotencyKey: send.idempotencyKey,
            requirementsVersion: send.plan.requirementsVersion,
            requirementResponses: answers,
            acknowledgeRelationshipWarnings: send.acknowledgeWarnings,
            closeUnfinalizedDrafts: send.discardDrafts,
            useOriginalDriveSection: send.useOriginalSection,
            expectedPreviousDriveFilingDate: send.useOriginalSection ? send.plan.previousFiling?.isoString : nil
        )
    }

    /// What a 409/422 refusal means for the person; codes the phone has no step for reload the task.
    static func refusal(_ dto: ApprovalErrorResponse?) -> ApprovalOutcome {
        guard let dto else { return .stale }
        switch dto.code {
        case blocked: return .blocked((dto.completion?.blockers ?? []).map(related))
        case warning: return .needsAcknowledgement((dto.completion?.warnings ?? []).map(related))
        case changed, notSatisfied:
            guard let items = dto.requirements else { return .stale }
            return .requirementsChanged(requirements(items), version: dto.requirementsVersion)
        default: return .stale
        }
    }

    private static func related(_ dto: CompletionDependencyResponse) -> RelatedTask {
        let friendly = dto.sourceTaskFriendlyId ?? 0
        let key = [TaskMapping.trimmed(dto.organizationAbbreviation), String(friendly)]
            .compactMap(\.self)
            .joined(separator: "-")
        return RelatedTask(
            id: dto.sourceTaskId ?? 0,
            key: key,
            title: TaskMapping.trimmed(dto.sourceTaskTitle) ?? "",
            statusName: TaskMapping.trimmed(dto.sourceTaskStatus),
            relationship: TaskMapping.trimmed(dto.sourceToTargetName) ?? TaskMapping.trimmed(dto.relationshipName)
        )
    }

    static func options(_ items: [RejectOptionResponse]) -> [SendBackOption] {
        items.compactMap { item in
            guard let id = item.taskApprovalId else { return nil }
            return SendBackOption(
                approvalId: id,
                name: TaskMapping.trimmed(item.displayName) ?? "",
                role: humanRole(TaskMapping.trimmed(item.roleName))
            )
        }
    }

    static func drafts(_ items: [TaskFormDraftResponse]) -> [FormDraft] {
        items.map { FormDraft(id: $0.id ?? 0, name: TaskMapping.trimmed($0.formName) ?? "") }
    }

    static func closure(_ dto: EmployeeClosureOptionsResponse) -> EmployeeClosure {
        EmployeeClosure(
            needsExpiration: dto.requiresNextExpirationDate ?? false,
            nextExpiration: TaskMapping.date(dto.nextExpirationDate),
            canMerge: dto.canMerge ?? false,
            pdfs: (dto.eligiblePdfs ?? []).compactMap { pdf in
                guard let id = pdf.employeeFileId, !id.isEmpty else { return nil }
                return ClosurePdf(id: id, name: TaskMapping.trimmed(pdf.fileName) ?? "", sizeBytes: pdf.size ?? 0)
            }
        )
    }

    static func late(_ dto: LateContextResponse) -> LateContext {
        LateContext(
            late: dto.isLate ?? false,
            canSubmit: dto.canSubmit ?? false,
            canReview: dto.canReview ?? false,
            reviewedByMe: dto.hasCurrentUserReviewed ?? false,
            satisfied: dto.satisfiesSubmission ?? false,
            justification: dto.justification.map { item in
                LateJustification(
                    id: item.id ?? 0,
                    reasonId: item.reasonCodeId ?? 0,
                    reasonName: TaskMapping.trimmed(item.reasonName),
                    explanation: item.explanation ?? "",
                    evidenceId: item.evidenceAttachmentId,
                    delayId: item.sourceTaskDelayId,
                    submittedBy: TaskMapping.trimmed(item.submittedByName),
                    returned: item.status?.caseInsensitiveCompare("Rejected") == .orderedSame
                )
            },
            suggestedDelay: dto.suggestedDelay.map { item in
                SuggestedDelay(
                    id: item.id ?? 0,
                    reasonId: item.reasonCodeId ?? 0,
                    reasonName: TaskMapping.trimmed(item.reasonName),
                    explanation: item.explanation ?? "",
                    evidenceId: item.evidenceAttachmentId
                )
            },
            reviews: (dto.reviews ?? []).map { item in
                LateReview(
                    name: TaskMapping.trimmed(item.reviewerName),
                    role: humanRole(TaskMapping.trimmed(item.reviewerRole)),
                    agreed: item.decision?.caseInsensitiveCompare(agree) == .orderedSame,
                    note: TaskMapping.trimmed(item.note)
                )
            }
        )
    }

    /// The web's late-justification filter: system codes unless hidden, agency codes while active.
    static func lateReasons(_ items: [ComplianceReasonResponse]) -> [ChangeReason] {
        items.compactMap { dto -> ChangeReason? in
            let offered = dto.isSystemCode == true ? dto.isHiddenFromUserSelection != true : dto.isActive == true
            guard offered, dto.canBeUsedForLateJustification == true, let id = dto.id,
                let name = TaskMapping.trimmed(dto.name)
            else { return nil }
            let preset = dto.presetExplanation.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            return ChangeReason(
                id: id,
                name: name,
                description: TaskMapping.trimmed(dto.userFacingDescription),
                requiresEvidence: dto.requiresEvidence ?? false,
                preset: preset
            )
        }
    }
}
