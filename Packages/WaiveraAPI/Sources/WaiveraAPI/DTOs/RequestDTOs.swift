import Foundation

// Mirrors of the sprout_api change-request contract: administrative requests
// (`api/admin/request`), task compliance requests (`api/tasks/{id}/extensions`, `/delays`,
// `/request-close`, `/compliance-request-eligibility`) and their reason lists. Request and
// decision times are UTC instants; due dates and delay periods are literal calendar dates.

/// `dto/Response/AdministrativeTransactionRequestResponse.cs`.
public struct AdminRequestResponse: Decodable, Sendable, Hashable {
    public var id: Int
    public var requesterName: String?
    public var requesterId: String?
    public var approverName: String?
    public var transactionType: String?
    public var status: String?
    public var requestTime: String?
    public var completionTime: String?
    public var taskId: Int?
    public var taskFriendlyId: Int?
    public var requiredAttachmentId: Int?
    public var taskTitle: String?
    public var transactionReasonText: String?
    public var participantRequest: ParticipantChangeResponse?
    public var timeOffDetails: TimeOffDetailsResponse?
    public var extensionReason: String?
    public var extensionOriginalDueDate: String?
    public var extensionRequestedDueDate: String?
    public var extensionApprovedDueDate: String?
    public var delayReason: String?
    public var delayStartDate: String?
    public var delayEndDate: String?
    public var isTrainingTask: Bool?

    public init(
        id: Int,
        requesterName: String? = nil,
        requesterId: String? = nil,
        approverName: String? = nil,
        transactionType: String? = nil,
        status: String? = nil,
        requestTime: String? = nil,
        completionTime: String? = nil,
        taskId: Int? = nil,
        taskFriendlyId: Int? = nil,
        requiredAttachmentId: Int? = nil,
        taskTitle: String? = nil,
        transactionReasonText: String? = nil,
        participantRequest: ParticipantChangeResponse? = nil,
        timeOffDetails: TimeOffDetailsResponse? = nil,
        extensionReason: String? = nil,
        extensionOriginalDueDate: String? = nil,
        extensionRequestedDueDate: String? = nil,
        extensionApprovedDueDate: String? = nil,
        delayReason: String? = nil,
        delayStartDate: String? = nil,
        delayEndDate: String? = nil,
        isTrainingTask: Bool? = nil
    ) {
        self.id = id
        self.requesterName = requesterName
        self.requesterId = requesterId
        self.approverName = approverName
        self.transactionType = transactionType
        self.status = status
        self.requestTime = requestTime
        self.completionTime = completionTime
        self.taskId = taskId
        self.taskFriendlyId = taskFriendlyId
        self.requiredAttachmentId = requiredAttachmentId
        self.taskTitle = taskTitle
        self.transactionReasonText = transactionReasonText
        self.participantRequest = participantRequest
        self.timeOffDetails = timeOffDetails
        self.extensionReason = extensionReason
        self.extensionOriginalDueDate = extensionOriginalDueDate
        self.extensionRequestedDueDate = extensionRequestedDueDate
        self.extensionApprovedDueDate = extensionApprovedDueDate
        self.delayReason = delayReason
        self.delayStartDate = delayStartDate
        self.delayEndDate = delayEndDate
        self.isTrainingTask = isTrainingTask
    }
}

/// `PagedResults<T>` inside an `ApiResponse`.
public struct PagedResults<T: Decodable & Sendable>: Decodable, Sendable {
    public var items: [T]
    public var totalCount: Int

    enum CodingKeys: String, CodingKey { case items, totalCount }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = container.lenientArray(T.self, forKey: .items)
        totalCount = container.lenientInt(forKey: .totalCount) ?? items.count
    }
}

/// `TaskComplianceRequestEligibilityResult`. Delay dates are literal `YYYY-MM-DD` strings.
public struct ComplianceEligibilityResponse: Decodable, Sendable, Hashable {
    public var taskId: Int?
    public var currentDueDate: String?
    public var isOverdue: Bool?
    public var hasPendingRequest: Bool?
    public var canRequestExtension: Bool?
    public var canRequestDelay: Bool?
    public var delayStartDate: String?
    public var delayEndDate: String?
    public var isDelayRenewal: Bool?
    public var hasQueuedApprovedDelay: Bool?
    public var isEmployeeTask: Bool?

    public init(
        taskId: Int? = nil,
        currentDueDate: String? = nil,
        isOverdue: Bool? = nil,
        hasPendingRequest: Bool? = nil,
        canRequestExtension: Bool? = nil,
        canRequestDelay: Bool? = nil,
        delayStartDate: String? = nil,
        delayEndDate: String? = nil,
        isDelayRenewal: Bool? = nil,
        hasQueuedApprovedDelay: Bool? = nil,
        isEmployeeTask: Bool? = nil
    ) {
        self.taskId = taskId
        self.currentDueDate = currentDueDate
        self.isOverdue = isOverdue
        self.hasPendingRequest = hasPendingRequest
        self.canRequestExtension = canRequestExtension
        self.canRequestDelay = canRequestDelay
        self.delayStartDate = delayStartDate
        self.delayEndDate = delayEndDate
        self.isDelayRenewal = isDelayRenewal
        self.hasQueuedApprovedDelay = hasQueuedApprovedDelay
        self.isEmployeeTask = isEmployeeTask
    }
}

/// `ComplianceReasonCode`, the fields a requester picks by.
public struct ComplianceReasonResponse: Decodable, Sendable, Hashable {
    public var id: Int64?
    public var name: String?
    public var userFacingDescription: String?
    public var isHiddenFromUserSelection: Bool?
    public var canBeUsedForExtension: Bool?
    public var canBeUsedForDelay: Bool?
    public var requiresEvidence: Bool?
    public var isActive: Bool?

    public init(
        id: Int64? = nil,
        name: String? = nil,
        userFacingDescription: String? = nil,
        isHiddenFromUserSelection: Bool? = nil,
        canBeUsedForExtension: Bool? = nil,
        canBeUsedForDelay: Bool? = nil,
        requiresEvidence: Bool? = nil,
        isActive: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.userFacingDescription = userFacingDescription
        self.isHiddenFromUserSelection = isHiddenFromUserSelection
        self.canBeUsedForExtension = canBeUsedForExtension
        self.canBeUsedForDelay = canBeUsedForDelay
        self.requiresEvidence = requiresEvidence
        self.isActive = isActive
    }
}

/// `TransactionReasonResponseDto` from `GET api/lookup/reasons?type=CLOSURE`.
public struct TransactionReasonResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var reasonText: String?

    public init(id: Int?, reasonText: String?) {
        self.id = id
        self.reasonText = reasonText
    }
}

/// `TaskExtensionRequestDto`. `requestedDueDate` is the chosen day at UTC midnight, as the web sends it.
public struct TaskExtensionRequest: Encodable, Sendable, Hashable {
    public var requestedDueDate: String
    public var reasonCodeId: Int64
    public var explanation: String
    public var evidenceAttachmentId: Int?

    public init(requestedDueDate: String, reasonCodeId: Int64, explanation: String, evidenceAttachmentId: Int?) {
        self.requestedDueDate = requestedDueDate
        self.reasonCodeId = reasonCodeId
        self.explanation = explanation
        self.evidenceAttachmentId = evidenceAttachmentId
    }
}

/// `TaskDelayRequestDto`. The period is echoed back as literal dates so a stale one is refused.
public struct TaskDelayRequest: Encodable, Sendable, Hashable {
    public var reasonCodeId: Int64
    public var explanation: String
    public var delayStartDate: String
    public var delayEndDate: String
    public var evidenceAttachmentId: Int?

    public init(
        reasonCodeId: Int64,
        explanation: String,
        delayStartDate: String,
        delayEndDate: String,
        evidenceAttachmentId: Int?
    ) {
        self.reasonCodeId = reasonCodeId
        self.explanation = explanation
        self.delayStartDate = delayStartDate
        self.delayEndDate = delayEndDate
        self.evidenceAttachmentId = evidenceAttachmentId
    }
}

/// The extension and delay endpoints answer with the new record's status.
public struct ComplianceRequestResult: Decodable, Sendable, Hashable {
    public var status: String?

    public init(status: String?) { self.status = status }
}

/// `CreateAdministrativeTransactionRequest` for `POST api/tasks/{id}/request-close`.
public struct TaskClosureRequest: Encodable, Sendable, Hashable {
    public var requesterId: String
    public var taskId: Int
    public var transactionReasonId: Int
    public var transactionReasonText: String
    public var transactionTypeId: String
    public var statusId: String

    public init(requesterId: String, taskId: Int, transactionReasonId: Int, transactionReasonText: String) {
        self.requesterId = requesterId
        self.taskId = taskId
        self.transactionReasonId = transactionReasonId
        self.transactionReasonText = transactionReasonText
        transactionTypeId = "Task Deletion Request"
        statusId = "PENDING"
    }
}

/// `POST api/Authentication/bootstrap` body. `identityTransition` re-reads roles only.
public struct AuthBootstrapRequest: Encodable, Sendable, Hashable {
    public var identityTransition: Bool

    public init(identityTransition: Bool = true) { self.identityTransition = identityTransition }
}

/// `dto/Response/AuthBootstrapResponseDto.cs`, only what gates what the phone offers: roles, the
/// role policies the web checks with `hasPolicyPermissionV2`, and the ABAC actions it checks with
/// `hasPermission`. The server re-checks every action, so these only decide what is shown.
public struct AuthBootstrapResponse: Decodable, Sendable, Hashable {
    public struct Roles: Decodable, Sendable, Hashable {
        public var isActiveOrganizationOwner: Bool
        public var employeeRoles: [String]
        public var organizationRoles: [OrganizationRole]

        public init(
            isActiveOrganizationOwner: Bool = false,
            employeeRoles: [String] = [],
            organizationRoles: [OrganizationRole] = []
        ) {
            self.isActiveOrganizationOwner = isActiveOrganizationOwner
            self.employeeRoles = employeeRoles
            self.organizationRoles = organizationRoles
        }

        enum CodingKeys: String, CodingKey { case isActiveOrganizationOwner, employeeRoles, organizationRoles }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isActiveOrganizationOwner = container.lenientBool(forKey: .isActiveOrganizationOwner)
            employeeRoles = container.lenientArray(JSONValue.self, forKey: .employeeRoles)
                .compactMap { $0["name"]?.stringValue }
            organizationRoles = container.lenientArray(OrganizationRole.self, forKey: .organizationRoles)
        }
    }

    public struct OrganizationRole: Decodable, Sendable, Hashable {
        public var name: String?
        public var systemKey: String?

        public init(name: String?, systemKey: String? = nil) {
            self.name = name
            self.systemKey = systemKey
        }
    }

    public struct AbacPolicy: Decodable, Sendable, Hashable {
        public var action: String?
        public var condition: String?

        public init(action: String?, condition: String? = nil) {
            self.action = action
            self.condition = condition
        }
    }

    public var roles: Roles
    public var permissions: [AbacPolicy]
    /// The `policyPermission.permissionKey` of every role policy.
    public var rolePolicyKeys: [String]
    /// Whether the role policy list is complete; a legacy account without policies passes.
    public var hasRolePolicies: Bool
    public var userAddedInRolePolicy: Bool

    public init(
        roles: Roles = Roles(),
        permissions: [AbacPolicy] = [],
        rolePolicyKeys: [String] = [],
        userAddedInRolePolicy: Bool = true
    ) {
        self.roles = roles
        self.permissions = permissions
        self.rolePolicyKeys = rolePolicyKeys
        hasRolePolicies = !rolePolicyKeys.isEmpty
        self.userAddedInRolePolicy = userAddedInRolePolicy
    }

    enum CodingKeys: String, CodingKey { case roles, permissions, rolePolicies, userAddedInRolePolicy }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roles = container.lenient(Roles.self, forKey: .roles) ?? Roles()
        permissions = container.lenientArray(AbacPolicy.self, forKey: .permissions)
        let policies = container.lenientArray(JSONValue.self, forKey: .rolePolicies)
        hasRolePolicies = !policies.isEmpty
        rolePolicyKeys = policies.compactMap { $0["policyPermission"]?["permissionKey"]?.stringValue }
        userAddedInRolePolicy = container.lenientBool(forKey: .userAddedInRolePolicy, default: true)
    }
}
