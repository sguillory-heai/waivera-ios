import Foundation
import WaiveraAPI

/// The signed-in employee. `id` (the backend user id) is the only "is this me" key; the
/// Firebase uid is kept for auth and diagnostics only (PLAN parity fix).
public struct CurrentUser: Codable, Sendable, Hashable {
    public var id: String
    public var firebaseUid: String
    public var email: String?
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var avatarURL: String?
    /// The employee's saved zone identifier, as the API returned it.
    public var timeZoneIdentifier: String?
    public var organization: Organization?
    public var roles: [String]
    /// The state client id shown on the profile (`UserWithRoleDto.ScId`); `nil` when unset.
    public var scId: String?

    public init(
        id: String,
        firebaseUid: String,
        email: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        displayName: String? = nil,
        avatarURL: String? = nil,
        timeZoneIdentifier: String? = nil,
        organization: Organization? = nil,
        roles: [String] = [],
        scId: String? = nil
    ) {
        self.id = id
        self.firebaseUid = firebaseUid
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.timeZoneIdentifier = timeZoneIdentifier
        self.organization = organization
        self.roles = roles
        self.scId = scId
    }

    public func isMe(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return userId == id
    }

    public var asChatUser: ChatUser {
        ChatUser(
            id: id,
            firstName: firstName,
            lastName: lastName,
            displayName: displayName,
            email: email,
            avatarURL: avatarURL
        )
    }

    /// The zone schedules render in (dates.md §2): the saved named zone, else America/Chicago.
    /// Fixed offsets are not named zones and fall back too.
    public var scheduleZone: ScheduleZone { ScheduleZone.resolve(savedIdentifier: timeZoneIdentifier) }

    public var scheduleTimeZone: TimeZone { scheduleZone.timeZone }

    /// The saved zone was missing or unusable; the UI says the fallback is in effect.
    public var isUsingFallbackTimeZone: Bool { scheduleZone.isFallback }
}

public struct Organization: Codable, Sendable, Hashable {
    public var id: Int
    public var name: String?
    public var abbreviation: String?
    public var address: String?
    public var contactNumber: String?
    public var isSandbox: Bool

    public init(
        id: Int,
        name: String?,
        abbreviation: String? = nil,
        address: String? = nil,
        contactNumber: String? = nil,
        isSandbox: Bool = false
    ) {
        self.id = id
        self.name = name
        self.abbreviation = abbreviation
        self.address = address
        self.contactNumber = contactNumber
        self.isSandbox = isSandbox
    }
}

/// The session gate (01 §1, §5).
public enum SessionState: Sendable, Hashable {
    /// Before the stored Firebase session has been checked.
    case loading
    case signedOut(WaiveraError?)
    /// Firebase signed in; the backend login is in flight.
    case bootstrapping
    /// The backend login failed for a reason other than 401; Firebase stays signed in so
    /// `retryBootstrap()` can try again (01 §2).
    case bootstrapFailed(WaiveraError)
    case passwordChangeRequired(CurrentUser)
    case onboardingRequired(CurrentUser)
    case signedIn(CurrentUser)
    /// The build has no API base URL or Firebase key.
    case configurationMissing

    public var user: CurrentUser? {
        switch self {
        case .passwordChangeRequired(let user), .onboardingRequired(let user), .signedIn(let user): user
        default: nil
        }
    }

    public var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}
