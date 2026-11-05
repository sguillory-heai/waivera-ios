import Foundation

/// `ParticipantInfoResponse` from `GET api/participants/{id}` (the web's Participant Profile tab).
/// Dates are `DateTime`s that carry a calendar day only. The response also carries the SSN's last
/// four and device fields; they are not mirrored, so the phone never holds them.
public struct ParticipantInfoResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var firstName: String?
    public var lastName: String?
    public var dateOfBirth: String?
    public var intakeType: String?
    public var region: ParticipantRegionResponse?
    public var deactivated: Bool?
    public var linkageDate: String?
    public var cpocDate: String?
    public var cpocEndDate: String?
    public var certificationDate: String?
    public var email: String?
    public var mobileNumber: String?
    public var waiver: ParticipantWaiverResponse?
    public var isCompliant: Bool?
}

/// `RegionResponse`.
public struct ParticipantRegionResponse: Decodable, Sendable, Hashable {
    public var regionId: Int?
    public var regionName: String?
}

/// `Waiver`.
public struct ParticipantWaiverResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var waiverName: String?
    public var code: String?
}

/// `PagedResult<TaskListResponse>` from `GET api/tasks/participant/{id}`, not enveloped. A row
/// that doesn't decode is skipped, not the whole page.
public struct ParticipantTasksResponse: Decodable, Sendable {
    public var items: [TaskListResponse]
    public var totalCount: Int

    enum CodingKeys: String, CodingKey { case items, totalCount }

    public init(items: [TaskListResponse] = [], totalCount: Int = 0) {
        self.items = items
        self.totalCount = totalCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = container.lenientArray(TaskListResponse.self, forKey: .items)
        totalCount = container.lenientInt(forKey: .totalCount) ?? 0
    }
}
