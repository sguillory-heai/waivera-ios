import Foundation
import WaiveraAPI

/// A staff directory entry (`get-username-list` carries only id and name, 06 §C1).
public struct DirectoryPerson: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A person's detail (`GetUserDetailsByUserID`).
public struct PersonProfile: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var email: String?
    public var avatarURL: String?
    public var phoneNumber: String?
    public var organizationName: String?
    public var roles: [String]
    public var timeZoneIdentifier: String?
    public var hireDate: CalendarDate?
    public var birthday: CalendarDate?

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName
        roles = []
    }

    public var chatUser: ChatUser {
        ChatUser(
            id: id,
            firstName: firstName,
            lastName: lastName,
            displayName: displayName,
            email: email,
            avatarURL: avatarURL
        )
    }
}

/// The own-profile screen (08 §1-5).
public struct EmployeeProfile: Codable, Sendable, Hashable {
    public var employeeId: String
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var email: String?
    public var avatarURL: String?
    public var phoneNumber: String?
    public var address: String?
    /// Date-only values; render without converting through any zone.
    public var hireDate: CalendarDate?
    public var joinDate: CalendarDate?
    public var birthday: CalendarDate?
    public var positions: [String]
    public var regions: [String]
    public var managers: [String]
    public var timeZoneIdentifier: String?
    /// Professional details (08 §3). `scId` comes from the session's user record; the profile
    /// endpoint does not carry it.
    public var scId: String?
    public var waiverFamilies: [String]
    public var agencies: [String]

    public init(employeeId: String) {
        self.employeeId = employeeId
        positions = []
        regions = []
        managers = []
        waiverFamilies = []
        agencies = []
    }

    enum CodingKeys: String, CodingKey {
        case employeeId, firstName, lastName, displayName, email, avatarURL, phoneNumber, address, hireDate
        case joinDate, birthday, positions, regions, managers, timeZoneIdentifier, scId, waiverFamilies, agencies
    }

    /// Cached profiles written before the professional fields existed still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        employeeId = try container.decode(String.self, forKey: .employeeId)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        hireDate = try container.decodeIfPresent(CalendarDate.self, forKey: .hireDate)
        joinDate = try container.decodeIfPresent(CalendarDate.self, forKey: .joinDate)
        birthday = try container.decodeIfPresent(CalendarDate.self, forKey: .birthday)
        positions = try container.decodeIfPresent([String].self, forKey: .positions) ?? []
        regions = try container.decodeIfPresent([String].self, forKey: .regions) ?? []
        managers = try container.decodeIfPresent([String].self, forKey: .managers) ?? []
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier)
        scId = try container.decodeIfPresent(String.self, forKey: .scId)
        waiverFamilies = try container.decodeIfPresent([String].self, forKey: .waiverFamilies) ?? []
        agencies = try container.decodeIfPresent([String].self, forKey: .agencies) ?? []
    }
}

/// Time-off balances. The API's first row doubles as the summary (08 §3).
public struct TimeOffOverview: Codable, Sendable, Hashable {
    public var remainingDays: Double
    public var allocated: Double?
    public var used: Double?
    public var pending: Double?
    /// 0...100, the share still available.
    public var remainingPercentage: Double
    public var entries: [TimeOffEntry]

    public init(remainingDays: Double = 0, remainingPercentage: Double = 100, entries: [TimeOffEntry] = []) {
        self.remainingDays = remainingDays
        self.remainingPercentage = remainingPercentage
        self.entries = entries
    }
}

public struct TimeOffEntry: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable, Hashable {
        case cancellationPending, rejected, approved, pending
    }

    public var id: Int
    public var leaveType: String?
    public var start: CalendarDate?
    public var end: CalendarDate?
    public var status: Status

    public init(id: Int, leaveType: String?, start: CalendarDate?, end: CalendarDate?, status: Status) {
        self.id = id
        self.leaveType = leaveType
        self.start = start
        self.end = end
        self.status = status
    }
}

public struct EmployeeFile: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var fileName: String?
    public var category: String?
    public var addedAt: Date?
    public var mimeType: String?
    public var size: Int64?

    public init(
        id: String,
        fileName: String?,
        category: String? = nil,
        addedAt: Date? = nil,
        mimeType: String? = nil,
        size: Int64? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.category = category
        self.addedAt = addedAt
        self.mimeType = mimeType
        self.size = size
    }
}
