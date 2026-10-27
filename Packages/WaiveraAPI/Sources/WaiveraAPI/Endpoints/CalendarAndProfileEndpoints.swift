import Foundation

/// `api/CalendarEvent/*`, `api/invitation/*`, `api/employee/*`, `api/TimeOff/*`,
/// `api/mobile-push/*` and `api/video/*`.
extension APIClient {
    /// The feed for `[start, end)`; callers pass the full rendered grid range (07 §2).
    public func calendarFeed(start: Date, end: Date) async throws -> CalendarFeedResponseDto {
        let request = APIRequest(
            .get,
            "api/CalendarEvent/GetAllEvent",
            query: [
                URLQueryItem(name: "startTime", value: WaiveraInstant.format(start)),
                URLQueryItem(name: "endTime", value: WaiveraInstant.format(end)),
            ]
        )
        return try await envelopedIfPresent(request) ?? CalendarFeedResponseDto(events: [], timeOff: [], holidays: [])
    }

    public func milestones() async throws -> [CalendarEmployeeMilestoneResponseDto] {
        let rows: LossyArray<CalendarEmployeeMilestoneResponseDto>? = try await envelopedIfPresent(
            APIRequest(.get, "api/CalendarEvent/milestones")
        )
        return rows?.elements ?? []
    }

    /// Accept or decline; `data: false` (also on 400/401) is a failure.
    public func respondToInvitation(_ body: InternalInvitationResponseReq) async throws {
        let accepted: Bool = try await enveloped(.json(.post, "api/invitation/AcceptDenyMeeting", body: body))
        guard accepted else { throw WaiveraError.invalidRequest }
    }

    public func employeeProfile(employeeId: String) async throws -> GetEmployeeProfileDto {
        try await enveloped(APIRequest(.get, "api/employee/getProfile/\(escape(employeeId))"))
    }

    public func timeOffForProfile(userId: String) async throws -> [TimeOffProfileItemDto] {
        let rows: LossyArray<TimeOffProfileItemDto>? = try await envelopedIfPresent(
            APIRequest(.get, "api/TimeOff/get-timeOffs-for-user-profile/\(escape(userId))")
        )
        return rows?.elements ?? []
    }

    public func employeeFiles(userId: String, pageSize: Int = 10) async throws -> [EmployeeFileDto] {
        let request = APIRequest(
            .get,
            "api/employee/get-employee-files",
            query: [
                URLQueryItem(name: "userId", value: userId),
                URLQueryItem(name: "pageNumber", value: "1"),
                URLQueryItem(name: "pageSize", value: String(pageSize)),
                URLQueryItem(name: "sortBy", value: "DateAdded"),
                URLQueryItem(name: "sortDirection", value: "desc"),
            ]
        )
        let page: ItemsPage<EmployeeFileDto>? = try await envelopedIfPresent(request)
        return page?.items ?? []
    }

    public func registerForPush(_ registration: MobilePushRegistrationRequest) async throws {
        let response: SuccessResponse = try await decode(.json(.post, "api/mobile-push/register", body: registration))
        guard response.success else { throw WaiveraError.invalidRequest }
    }

    public func unregisterFromPush(deviceID: String) async throws {
        try await send(
            .json(.post, "api/mobile-push/unregister", body: MobilePushUnregisterRequest(deviceID: deviceID))
        )
    }

    public func createMeetingRoom(_ body: CreateMeetingRoomRequest) async throws -> CreateMeetingRoomResponse {
        let response: CreateMeetingRoomResponse = try await enveloped(
            .json(.post, "api/video/createmeetingroom", body: body)
        )
        guard let roomId = response.roomId, !roomId.isEmpty else { throw WaiveraError.invalidResponse }
        return response
    }
}
