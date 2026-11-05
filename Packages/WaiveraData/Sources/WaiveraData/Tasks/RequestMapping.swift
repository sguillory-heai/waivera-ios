import Foundation
import WaiveraAPI

/// Turns the server's request shapes into the phone's, and decides what to offer with the same
/// rules the web uses (sprout_web `hasPolicyPermissionV2`, `doesUserHavePermission`, the Admin
/// Requests sidebar rule and the task list's pending-approvals rule).
enum RequestMapping {
    static let createExtension = "admin_request:create:task_extension"
    static let createDeletion = "admin_request:create:task_deletion"
    static let createTimeOff = "admin_request:create:time_off"
    static let caseFileDownload = "case_file:download"
    static let employeeFileDownload = "employee_file:download"
    private static let externalTrainingView = "admin_request:view:external_training"
    private static let externalTrainingApprove = "admin_request:approve:external_training"
    private static let officeManager = "Office Manager"
    /// The web's role order for the task list's pending-approvals default.
    private static let rankedRoles = ["ADMIN", "OWNER", "PROGRAM MANAGER", "SUPERVISOR", "SC", "ASSESSOR"]

    static func request(_ dto: AdminRequestResponse) -> ChangeRequest {
        let kind = RequestKind(typeName: dto.transactionType)
        // A closure keeps its picked reason (or comment) in the reason text; the other kinds
        // keep the picked code name apart and the requester's words in the reason text.
        let reason: String? =
            switch kind {
            case .moreTime: TaskMapping.trimmed(dto.extensionReason)
            case .delay: TaskMapping.trimmed(dto.delayReason)
            default: nil
            }
        return ChangeRequest(
            id: dto.id,
            kind: kind,
            typeName: TaskMapping.trimmed(dto.transactionType) ?? "",
            status: RequestStatus(name: dto.status),
            requesterId: dto.requesterId,
            requesterName: TaskMapping.trimmed(dto.requesterName) ?? "",
            approverName: TaskMapping.trimmed(dto.approverName),
            requestedAt: TaskMapping.instant(dto.requestTime),
            decidedAt: TaskMapping.instant(dto.completionTime),
            taskId: dto.taskId,
            taskTitle: TaskMapping.trimmed(dto.taskTitle),
            reason: reason,
            explanation: TaskMapping.trimmed(dto.transactionReasonText),
            currentDue: TaskMapping.date(dto.extensionOriginalDueDate),
            requestedDue: TaskMapping.date(dto.extensionApprovedDueDate ?? dto.extensionRequestedDueDate),
            delayStart: TaskMapping.date(dto.delayStartDate),
            delayEnd: TaskMapping.date(dto.delayEndDate),
            isTrainingTask: dto.isTrainingTask ?? false,
            timeOff: kind.isTimeOff ? dto.timeOffDetails.map(ApprovalMapping.timeOff) : nil,
            profile: kind == .profileChange ? (dto.participantRequest.map(ApprovalMapping.profile) ?? []) : []
        )
    }

    /// sprout_web `getEligibleDelayPeriod`: a missing or reversed period fails closed.
    static func options(_ dto: ComplianceEligibilityResponse, taskId: Int) -> ChangeOptions {
        let start = TaskMapping.date(dto.delayStartDate)
        let end = TaskMapping.date(dto.delayEndDate)
        let pending = dto.hasPendingRequest ?? false
        let open = (dto.canRequestDelay ?? false) && !pending && !(dto.hasQueuedApprovedDelay ?? false)
        var delay: DelayPeriod?
        if open, let start, let end, end > start {
            delay = DelayPeriod(start: start, end: end, renewal: dto.isDelayRenewal ?? false)
        }
        return ChangeOptions(
            taskId: dto.taskId ?? taskId,
            currentDue: TaskMapping.date(dto.currentDueDate),
            canAskMoreTime: (dto.canRequestExtension ?? false) && !pending,
            delay: delay,
            hasPendingRequest: pending
        )
    }

    static func reasons(_ items: [ComplianceReasonResponse], forDelay: Bool) -> [ChangeReason] {
        items.compactMap { dto -> ChangeReason? in
            guard dto.isActive == true, dto.isHiddenFromUserSelection != true, let id = dto.id,
                let name = TaskMapping.trimmed(dto.name),
                (forDelay ? dto.canBeUsedForDelay : dto.canBeUsedForExtension) == true
            else { return nil }
            return ChangeReason(
                id: id,
                name: name,
                description: TaskMapping.trimmed(dto.userFacingDescription),
                requiresEvidence: dto.requiresEvidence ?? false
            )
        }
    }

    static func closureReasons(_ items: [TransactionReasonResponse]) -> [ChangeReason] {
        items.compactMap { dto -> ChangeReason? in
            guard let id = dto.id, let text = TaskMapping.trimmed(dto.reasonText) else { return nil }
            // The web's closure modal asks for a comment on any reason containing "other".
            return ChangeReason(
                id: Int64(id),
                name: text,
                description: nil,
                requiresEvidence: false,
                needsComment: text.lowercased().contains("other")
            )
        }
    }

    /// sprout_web `RequestDelayModal`: only real, present files can be cited.
    static func files(_ items: [TaskAttachmentResponse]) -> [TaskFileRef] {
        items
            .filter { $0.id > 0 && TaskMapping.trimmed($0.file?.id) != nil && $0.employeeFileDeleted != true }
            .map { TaskFileRef(attachmentId: $0.id, name: TaskMapping.trimmed($0.file?.fileName) ?? "File \($0.id)") }
    }

    static func access(_ dto: AuthBootstrapResponse) -> RequestAccess {
        let employeeRoles = dto.roles.employeeRoles.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        let isOwnerOrAdmin =
            dto.roles.isActiveOrganizationOwner
            || dto.roles.organizationRoles.contains { $0.systemKey == "ORG_OWNER" }
            || employeeRoles.contains { $0 == "OWNER" || $0 == "ADMIN" }
        let isOfficeManager = dto.roles.organizationRoles.contains { $0.name == officeManager }
        let externalTraining = hasAbac(dto, externalTrainingView) || hasAbac(dto, externalTrainingApprove)
        let highest = rankedRoles.first { employeeRoles.contains($0) }
        return RequestAccess(
            canAskMoreTime: hasPolicy(dto, createExtension),
            canAskClosure: hasPolicy(dto, createDeletion),
            showsRequests: isOwnerOrAdmin || !isOfficeManager || externalTraining,
            includePendingApprovals: !employeeRoles.contains("SC") && highest != nil && highest != "PROGRAM MANAGER",
            canDownloadCaseFiles: hasPolicy(dto, caseFileDownload),
            canDownloadEmployeeFiles: hasPolicy(dto, employeeFileDownload),
            canRequestTimeOff: hasPolicy(dto, createTimeOff),
            loaded: true
        )
    }

    /// sprout_web `hasPolicyPermissionV2` with no scope asked; legacy accounts without policies pass.
    static func hasPolicy(_ dto: AuthBootstrapResponse, _ key: String) -> Bool {
        dto.rolePolicyKeys.contains(key) || (!dto.hasRolePolicies && !dto.userAddedInRolePolicy)
    }

    /// sprout_web `doesUserHavePermission` without a resource: wildcards match, conditions must be empty.
    private static func hasAbac(_ dto: AuthBootstrapResponse, _ action: String) -> Bool {
        dto.permissions.contains { policy in
            let granted = policy.action?.trimmingCharacters(in: .whitespaces) ?? ""
            let matches: Bool =
                if granted == "*" {
                    true
                } else if granted.hasSuffix(":*") {
                    action.hasPrefix(String(granted.dropLast()))
                } else {
                    granted.caseInsensitiveCompare(action) == .orderedSame
                }
            let condition = policy.condition?.trimmingCharacters(in: .whitespaces) ?? ""
            return matches && (condition.isEmpty || condition == "{}" || condition == "null")
        }
    }
}
