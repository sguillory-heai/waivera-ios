import Foundation

// Mirrors of the sprout_api contracts a reviewer needs for every admin request type: time off
// (`EmployeeTimeOffResponseDto`, leave balances, settings, preview), participant profile changes
// (`VIewParticipantRequest`) and external training credit. Times are UTC instants, sometimes
// without a zone suffix; leave dates are literal calendar dates.

/// `EmployeeTimeOffResponseDto`, the fields a reviewer sees.
public struct TimeOffDetailsResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var timeOffStartDate: String?
    public var timeOffEndDate: String?
    public var typeOfLeave: String?
    public var typeOfLeaveId: Int?
    public var comment: String?
    /// `FULL_DAY` or `PARTIAL_DAY`.
    public var requestType: String?
    public var durationMinutes: Int?
    public var intelligenceSnapshotJson: String?
    public var currentIntelligenceJson: String?
    public var reviewRevision: Int?
    public var impactAcknowledgedRevision: Int?
    public var impactAcknowledgedAt: String?

    public init(
        id: Int? = nil, timeOffStartDate: String? = nil, timeOffEndDate: String? = nil, typeOfLeave: String? = nil,
        typeOfLeaveId: Int? = nil, comment: String? = nil, requestType: String? = nil, durationMinutes: Int? = nil,
        intelligenceSnapshotJson: String? = nil, currentIntelligenceJson: String? = nil, reviewRevision: Int? = nil,
        impactAcknowledgedRevision: Int? = nil, impactAcknowledgedAt: String? = nil
    ) {
        self.id = id
        self.timeOffStartDate = timeOffStartDate
        self.timeOffEndDate = timeOffEndDate
        self.typeOfLeave = typeOfLeave
        self.typeOfLeaveId = typeOfLeaveId
        self.comment = comment
        self.requestType = requestType
        self.durationMinutes = durationMinutes
        self.intelligenceSnapshotJson = intelligenceSnapshotJson
        self.currentIntelligenceJson = currentIntelligenceJson
        self.reviewRevision = reviewRevision
        self.impactAcknowledgedRevision = impactAcknowledgedRevision
        self.impactAcknowledgedAt = impactAcknowledgedAt
    }
}

/// sprout_web `LeaveIntelligencePreview`, stored as JSON text on the time-off request.
public struct LeaveIntelligenceResponse: Decodable, Sendable, Hashable {
    public var overdueCount: Int?
    public var dueDuringLeaveCount: Int?
    public var warnings: [LeaveWarningResponse]?

    public init(overdueCount: Int? = nil, dueDuringLeaveCount: Int? = nil, warnings: [LeaveWarningResponse]? = nil) {
        self.overdueCount = overdueCount
        self.dueDuringLeaveCount = dueDuringLeaveCount
        self.warnings = warnings
    }
}

public struct LeaveWarningResponse: Decodable, Sendable, Hashable {
    public var code: String?
    public var message: String?

    public init(code: String? = nil, message: String? = nil) {
        self.code = code
        self.message = message
    }
}

/// `VIewParticipantRequest`; the server's spelling of the two profiles is kept.
public struct ParticipantChangeResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var participantId: Int?
    public var newProfileChanegs: ParticipantProfileResponse?
    public var orignalProfile: ParticipantProfileResponse?

    public init(
        id: Int? = nil, participantId: Int? = nil, newProfileChanegs: ParticipantProfileResponse? = nil,
        orignalProfile: ParticipantProfileResponse? = nil
    ) {
        self.id = id
        self.participantId = participantId
        self.newProfileChanegs = newProfileChanegs
        self.orignalProfile = orignalProfile
    }
}

/// `NewProfileChanegsDto` / `OrignalProfileDto`: the fields the web compares.
public struct ParticipantProfileResponse: Decodable, Sendable, Hashable {
    public var dateOfBirth: String?
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var mobileNumber: String?
    public var waiverName: String?
    public var waiverId: Int?
    public var participantSsnLast4: String?
    public var certificationDate: String?
    public var cpocDate: String?
    public var cpocEndDate: String?

    public init(
        dateOfBirth: String? = nil, firstName: String? = nil, lastName: String? = nil, email: String? = nil,
        mobileNumber: String? = nil, waiverName: String? = nil, waiverId: Int? = nil,
        participantSsnLast4: String? = nil, certificationDate: String? = nil, cpocDate: String? = nil,
        cpocEndDate: String? = nil
    ) {
        self.dateOfBirth = dateOfBirth
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.mobileNumber = mobileNumber
        self.waiverName = waiverName
        self.waiverId = waiverId
        self.participantSsnLast4 = participantSsnLast4
        self.certificationDate = certificationDate
        self.cpocDate = cpocDate
        self.cpocEndDate = cpocEndDate
    }
}

/// `TimeOffActionDto` for both `TimeOff/approve-reject` and the profile change route.
public struct RequestActionBody: Encodable, Sendable, Hashable {
    public var action: String
    public var reason: String

    public init(action: String, reason: String) {
        self.action = action
        self.reason = reason
    }
}

/// `EmployeeLeaveSummary` from `leave-management/employees/{id}/balances` (balances only).
public struct LeaveBalancesResponse: Decodable, Sendable, Hashable {
    public var balances: [LeaveBalanceResponse]?

    public init(balances: [LeaveBalanceResponse]? = nil) { self.balances = balances }
}

public struct LeaveBalanceResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var name: String?
    public var tracksBalance: Bool?
    public var availableMinutes: Int?

    public init(id: Int? = nil, name: String? = nil, tracksBalance: Bool? = nil, availableMinutes: Int? = nil) {
        self.id = id
        self.name = name
        self.tracksBalance = tracksBalance
        self.availableMinutes = availableMinutes
    }
}

/// `leave-management/settings`, the zone partial days are told in.
public struct LeaveSettingsResponse: Decodable, Sendable, Hashable {
    public var timeZone: String?

    public init(timeZone: String? = nil) { self.timeZone = timeZone }
}

/// `LeaveRequestTypeDto` from `GET api/TimeOff/all` (a bare list, active types only).
public struct LeaveTypeResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var requestType: String?
    public var isActive: Bool?
    public var isDeleted: Bool?

    public init(id: Int? = nil, requestType: String? = nil, isActive: Bool? = nil, isDeleted: Bool? = nil) {
        self.id = id
        self.requestType = requestType
        self.isActive = isActive
        self.isDeleted = isDeleted
    }
}

/// `LeaveRequestBalancePreviewDto`; times are ISO instants, as the web sends them.
public struct LeavePreviewBody: Encodable, Sendable, Hashable {
    public var timeOffId: Int
    public var employeeId: String
    public var leaveTypeId: Int
    public var startTime: String
    public var endTime: String
    public var requestType: String

    public init(
        timeOffId: Int = 0, employeeId: String, leaveTypeId: Int, startTime: String, endTime: String,
        requestType: String
    ) {
        self.timeOffId = timeOffId
        self.employeeId = employeeId
        self.leaveTypeId = leaveTypeId
        self.startTime = startTime
        self.endTime = endTime
        self.requestType = requestType
    }
}

/// `LeaveManagementService.PreviewRequestAsync`, including its blocked shape.
public struct LeavePreviewResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var tracksBalance: Bool?
    public var requestedMinutes: Int?
    public var beforeMinutes: Int?
    public var afterMinutes: Int?
    public var isRequestable: Bool?
    public var blockingCode: String?
    public var intelligence: LeaveIntelligenceResponse?

    public init(
        id: Int? = nil, tracksBalance: Bool? = nil, requestedMinutes: Int? = nil, beforeMinutes: Int? = nil,
        afterMinutes: Int? = nil, isRequestable: Bool? = nil, blockingCode: String? = nil,
        intelligence: LeaveIntelligenceResponse? = nil
    ) {
        self.id = id
        self.tracksBalance = tracksBalance
        self.requestedMinutes = requestedMinutes
        self.beforeMinutes = beforeMinutes
        self.afterMinutes = afterMinutes
        self.isRequestable = isRequestable
        self.blockingCode = blockingCode
        self.intelligence = intelligence
    }
}

/// `EmployeeTimeOffDto`; id 0 creates a request.
public struct TimeOffBody: Encodable, Sendable, Hashable {
    public var id: Int
    public var userId: String
    public var typeOfLeave: Int
    public var comment: String?
    public var timeOffStartTime: String
    public var timeOffEndTime: String
    public var requestType: String

    public init(
        id: Int = 0, userId: String, typeOfLeave: Int, comment: String?, timeOffStartTime: String,
        timeOffEndTime: String, requestType: String
    ) {
        self.id = id
        self.userId = userId
        self.typeOfLeave = typeOfLeave
        self.comment = comment
        self.timeOffStartTime = timeOffStartTime
        self.timeOffEndTime = timeOffEndTime
        self.requestType = requestType
    }
}

/// `TrainingExternalService.RequestDetailsAsync` (or the standalone credit's), a bare object.
/// `standaloneCreditId` marks a credit reviewed on the web's training page instead.
public struct TrainingCreditResponse: Decodable, Sendable, Hashable {
    public var courseTitle: String?
    public var employeeName: String?
    public var trainerName: String?
    public var provider: String?
    public var completedDate: String?
    public var hours: Double?
    public var fileName: String?
    public var status: String?
    public var revision: Int?
    public var canApprove: Bool?
    public var requiresOverrideReason: Bool?
    public var approvalBlockedReason: String?
    public var uploadedForEmployee: Bool?
    public var submittedByName: String?
    public var standaloneCreditId: Int?

    public init(
        courseTitle: String? = nil, employeeName: String? = nil, trainerName: String? = nil, provider: String? = nil,
        completedDate: String? = nil, hours: Double? = nil, fileName: String? = nil, status: String? = nil,
        revision: Int? = nil, canApprove: Bool? = nil, requiresOverrideReason: Bool? = nil,
        approvalBlockedReason: String? = nil, uploadedForEmployee: Bool? = nil, submittedByName: String? = nil,
        standaloneCreditId: Int? = nil
    ) {
        self.courseTitle = courseTitle
        self.employeeName = employeeName
        self.trainerName = trainerName
        self.provider = provider
        self.completedDate = completedDate
        self.hours = hours
        self.fileName = fileName
        self.status = status
        self.revision = revision
        self.canApprove = canApprove
        self.requiresOverrideReason = requiresOverrideReason
        self.approvalBlockedReason = approvalBlockedReason
        self.uploadedForEmployee = uploadedForEmployee
        self.submittedByName = submittedByName
        self.standaloneCreditId = standaloneCreditId
    }
}

/// `TrainingCreditDecision`.
public struct TrainingDecisionBody: Encodable, Sendable, Hashable {
    public var revision: Int
    public var approve: Bool
    public var reason: String

    public init(revision: Int, approve: Bool, reason: String) {
        self.revision = revision
        self.approve = approve
        self.reason = reason
    }
}
