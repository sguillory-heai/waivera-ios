import Foundation

/// Mirrors `GetEmployeeProfileDto` (`GET /api/employee/getProfile/{employeeId}`).
public struct GetEmployeeProfileDto: Codable, Sendable, Equatable {
    public struct Reporter: Codable, Sendable, Equatable {
        public var employeeId: String?
        public var name: String?
        public var avatar: String?
    }

    public struct Region: Codable, Sendable, Equatable {
        public var regionId: Int?
        public var name: String?
    }

    public var employeeId: String
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var displayName: String?
    public var avatarURL: String?
    public var phoneNumber: String?
    public var joinDate: CalendarDate?
    public var hireDate: CalendarDate?
    public var address: String?
    public var positions: [String]?
    public var reporters: [Reporter]?
    public var regions: [Region]?
    public var agencyNames: [String]?
    public var waiverFamilyIds: [Int]?
    public var waiverFamilies: [String]?
    public var birthday: CalendarDate?
    /// The employee's saved IANA zone.
    public var timezone: String?
}

/// One row of `GET /api/TimeOff/get-timeOffs-for-user-profile/{userId}`. The balance
/// roll-ups repeat on every row (08 §3).
public struct TimeOffProfileItemDto: Codable, Sendable, Equatable {
    public var id: Int
    public var timeOffStartDate: CalendarDate?
    public var timeOffEndDate: CalendarDate?
    public var typeOfLeave: String?
    public var comment: String?
    public var isApproved: Bool?
    public var isRejected: Bool?
    public var isCancellationPending: Bool?
    public var rejectionReason: String?
    public var requestType: String?
    public var pendingTimeOffCount: Double?
    public var approvedLeaveCount: Double?
    public var allocatedLeaveCount: Double?
    public var remainingLeaveCount: Double?
    public var remainingLeaveDays: Double?
    public var remainingLeaveHours: Double?
    public var usedLeaveDays: Double?
    public var usedLeaveHours: Double?
    public var usedLeavePercentage: Double?
    public var remainingLeavePercentage: Double?
}

/// One row of `GET /api/employee/get-employee-files`.
public struct EmployeeFileDto: Codable, Sendable, Equatable {
    public var id: String
    public var fileName: String?
    public var documentCategoryName: String?
    public var dateAdded: Date?
    public var fileUrl: String?
    public var mimeType: String?
    public var size: Int64?
    public var userId: String?
    public var uploadedByName: String?

    enum CodingKeys: String, CodingKey {
        case id, fileName, documentCategoryName, dateAdded, fileUrl, mimeType, size, userId, uploadedByName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(LenientID.self, forKey: .id).value
        fileName = container.lenient(String.self, forKey: .fileName)
        documentCategoryName = container.lenient(String.self, forKey: .documentCategoryName)
        dateAdded = container.lenient(Date.self, forKey: .dateAdded)
        fileUrl = container.lenient(String.self, forKey: .fileUrl)
        mimeType = container.lenient(String.self, forKey: .mimeType)
        size = container.lenient(Int64.self, forKey: .size)
        userId = container.lenient(String.self, forKey: .userId)
        uploadedByName = container.lenient(String.self, forKey: .uploadedByName)
    }
}
