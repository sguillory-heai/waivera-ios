import Foundation
import WaiveraAPI

public enum ProfileMapper {
    public static func currentUser(
        login: UserLoginResponseDto,
        identity: FirebaseIdentity,
        details: UserWithRoleDto?,
        organization: Organization?
    ) -> CurrentUser {
        CurrentUser(
            id: login.userId,
            firebaseUid: identity.uid,
            email: details?.email ?? identity.email,
            firstName: details?.firstName?.nilIfBlank,
            lastName: details?.lastName?.nilIfBlank,
            displayName: details?.displayName?.nilIfBlank ?? identity.displayName,
            avatarURL: details?.avatarURL?.nilIfBlank,
            timeZoneIdentifier: details?.timezone?.nilIfBlank,
            organization: organization,
            roles: details?.roles ?? [],
            scId: details?.scId?.nilIfBlank
        )
    }

    public static func organization(_ dto: OrganizationResponse) -> Organization {
        Organization(
            id: dto.id,
            name: dto.name?.nilIfBlank,
            abbreviation: dto.abbreviation?.nilIfBlank,
            isSandbox: dto.isSandbox ?? false
        )
    }

    public static func person(_ dto: UserWithRoleDto) -> PersonProfile {
        var person = PersonProfile(id: dto.id, displayName: dto.displayName?.nilIfBlank)
        person.firstName = dto.firstName?.nilIfBlank
        person.lastName = dto.lastName?.nilIfBlank
        person.email = dto.email?.nilIfBlank
        person.avatarURL = dto.avatarURL?.nilIfBlank
        person.phoneNumber = dto.phoneNumber?.nilIfBlank
        person.organizationName = (dto.organizationName ?? dto.organization?.name)?.nilIfBlank
        person.roles = (dto.roles ?? []).compactMap(\.nilIfBlank)
        if person.roles.isEmpty, let role = dto.organizationRole?.name?.nilIfBlank { person.roles = [role] }
        person.timeZoneIdentifier = dto.timezone?.nilIfBlank
        person.hireDate = dto.hireDate ?? dto.joinDate
        person.birthday = dto.birthday
        return person
    }

    public static func profile(_ dto: GetEmployeeProfileDto) -> EmployeeProfile {
        var profile = EmployeeProfile(employeeId: dto.employeeId)
        profile.firstName = dto.firstName?.nilIfBlank
        profile.lastName = dto.lastName?.nilIfBlank
        profile.displayName = dto.displayName?.nilIfBlank
        profile.email = dto.email?.nilIfBlank
        profile.avatarURL = dto.avatarURL?.nilIfBlank
        profile.phoneNumber = dto.phoneNumber?.nilIfBlank
        profile.address = dto.address?.nilIfBlank
        profile.hireDate = dto.hireDate
        profile.joinDate = dto.joinDate
        profile.birthday = dto.birthday
        profile.positions = (dto.positions ?? []).compactMap(\.nilIfBlank)
        profile.regions = (dto.regions ?? []).compactMap { $0.name?.nilIfBlank }
        profile.managers = (dto.reporters ?? []).compactMap { $0.name?.nilIfBlank }
        profile.timeZoneIdentifier = dto.timezone?.nilIfBlank
        profile.agencies = (dto.agencyNames ?? []).compactMap(\.nilIfBlank)
        profile.waiverFamilies = (dto.waiverFamilies ?? []).compactMap(\.nilIfBlank)
        return profile
    }

    /// Element 0 is both the summary and the first row (08 §3).
    public static func timeOff(_ rows: [TimeOffProfileItemDto]) -> TimeOffOverview {
        var overview = TimeOffOverview(entries: rows.map(entry))
        guard let summary = rows.first else { return overview }
        overview.remainingDays = summary.remainingLeaveDays ?? summary.remainingLeaveCount ?? 0
        overview.allocated = summary.allocatedLeaveCount
        overview.used = summary.usedLeaveDays ?? summary.approvedLeaveCount
        overview.pending = summary.pendingTimeOffCount
        let used = min(max(summary.usedLeavePercentage ?? 0, 0), 100)
        overview.remainingPercentage = 100 - used
        return overview
    }

    public static func entry(_ dto: TimeOffProfileItemDto) -> TimeOffEntry {
        let status: TimeOffEntry.Status =
            if dto.isCancellationPending == true {
                .cancellationPending
            } else if dto.isRejected == true {
                .rejected
            } else if dto.isApproved == true {
                .approved
            } else {
                .pending
            }
        return TimeOffEntry(
            id: dto.id,
            leaveType: dto.typeOfLeave?.nilIfBlank,
            start: dto.timeOffStartDate,
            end: dto.timeOffEndDate,
            status: status
        )
    }

    public static func file(_ dto: EmployeeFileDto) -> EmployeeFile {
        EmployeeFile(
            id: dto.id,
            fileName: dto.fileName?.nilIfBlank,
            category: dto.documentCategoryName?.nilIfBlank,
            addedAt: dto.dateAdded,
            mimeType: dto.mimeType?.nilIfBlank,
            size: dto.size
        )
    }
}
