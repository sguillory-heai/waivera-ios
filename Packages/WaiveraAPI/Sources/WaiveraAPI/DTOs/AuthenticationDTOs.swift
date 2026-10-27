import Foundation

/// Mirrors `UserLoginResponseDto` (`data` of `GET /api/Authentication/login`, gap G-02).
/// Flags are decoded leniently (`true`, `"true"`, `1`) and `userId` may be a number. `userId`
/// is required: without it every "is this me" check would quietly fail (IF-08). A PascalCase
/// `UserID`, which the decoder's key conversion turns into `userID`, is accepted too.
public struct UserLoginResponseDto: Codable, Sendable, Equatable {
    public var requiresPasswordChange: Bool
    public var userId: String
    public var requiresOnboarding: Bool

    public init(requiresPasswordChange: Bool, userId: String, requiresOnboarding: Bool) {
        self.requiresPasswordChange = requiresPasswordChange
        self.userId = userId
        self.requiresOnboarding = requiresOnboarding
    }

    enum CodingKeys: String, CodingKey {
        case requiresPasswordChange, userId, requiresOnboarding
    }

    private enum AliasKeys: String, CodingKey {
        case userID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requiresPasswordChange = container.lenientBool(forKey: .requiresPasswordChange)
        requiresOnboarding = container.lenientBool(forKey: .requiresOnboarding)
        let alias = try decoder.container(keyedBy: AliasKeys.self)
        let id =
            container.lenient(LenientID.self, forKey: .userId)?.value
            ?? alias.lenient(LenientID.self, forKey: .userID)?.value
        guard let id, !id.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.userId,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "userId is required")
            )
        }
        userId = id
    }
}

public struct NamedReference: Codable, Sendable, Equatable {
    public var id: Int?
    public var name: String?
    public var abbreviation: String?
}

/// `regions[]` on `UserWithRoleDto`.
public struct UserRegionDto: Codable, Sendable, Equatable {
    public var id: Int?
    public var regionName: String?
}

/// Mirrors `UserWithRoleDto` (`dto/Response/UserWithRoleDto.cs`).
public struct UserWithRoleDto: Codable, Sendable, Equatable {
    public var id: String
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var displayName: String?
    public var avatarURL: String?
    public var scId: String?
    public var deactivated: Bool?
    /// `DateTime` on the wire but a calendar date in meaning (dates.md §3 caveat).
    public var joinDate: CalendarDate?
    public var hireDate: CalendarDate?
    public var organizationId: Int?
    public var organizationName: String?
    public var organization: NamedReference?
    public var organizationRole: NamedReference?
    public var phoneNumber: String?
    public var managerId: String?
    public var managerName: String?
    public var roles: [String]?
    public var regions: [UserRegionDto]?
    public var teams: [NamedReference]?
    public var waiverFamilyIds: [Int]?
    public var waiverFamilyCode: [String]?
    /// The employee's saved IANA zone.
    public var timezone: String?
    public var caseloadCapacity: Int?
    public var isCaseloadCapacityUnlimited: Bool?
    public var birthday: CalendarDate?
}

/// Mirrors `UpdateContactAndTimezoneRequest`.
public struct UpdateContactAndTimezoneRequest: Codable, Sendable, Equatable {
    public var phoneNumber: String?
    public var preferredTimeZone: String?

    public init(phoneNumber: String?, preferredTimeZone: String?) {
        self.phoneNumber = phoneNumber
        self.preferredTimeZone = preferredTimeZone
    }
}

/// Mirrors `OrganizationDto` (`GET /api/Authentication/OrganizationDetails`).
public struct OrganizationDto: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String?
    public var address: String?
    public var contactNumber: String?
}

/// Mirrors `OrganizationResponse` (bare `GET /api/users/organization`).
public struct OrganizationResponse: Codable, Sendable, Equatable {
    public var id: Int
    public var name: String?
    public var abbreviation: String?
    public var atRiskWindowDays: Int?
    public var defaultPtoDays: Double?
    public var isSandbox: Bool?
}

/// Mirrors `GetUserNameResponseVM` (`get-username-list`, the staff directory).
public struct GetUserNameResponseVM: Codable, Sendable, Equatable {
    public var userId: String
    public var userName: String?

    enum CodingKeys: String, CodingKey { case userId, userName }

    public init(userId: String, userName: String?) {
        self.userId = userId
        self.userName = userName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(LenientID.self, forKey: .userId).value
        userName = container.lenient(String.self, forKey: .userName)
    }
}

/// Mirrors `GetUserNameResponseDBVM` (`get-combined-user-list`; includes participants).
public struct GetUserNameResponseDBVM: Codable, Sendable, Equatable {
    public var userId: String
    public var userName: String?
    public var type: String?
}

/// Mirrors `ChangePasswordRequest`-style bodies are undefined server-side (01 §5); the app
/// changes the password through Firebase and then calls `confirm-password-change`.
public struct EmptyBody: Codable, Sendable, Equatable {
    public init() {}
}
