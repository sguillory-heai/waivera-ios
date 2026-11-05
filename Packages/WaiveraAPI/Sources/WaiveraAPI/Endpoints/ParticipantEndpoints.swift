import Foundation

/// The read-only participant profile (web Participant Profile tab and Recent Tasks).
extension APIClient {
    public static let participantTaskPageSize = 50

    /// 403 unless the caller may view this participant (`participant:view` or legacy `view:participant`).
    public func participant(id: Int) async throws -> ParticipantInfoResponse {
        try await decode(APIRequest(.get, "api/participants/\(id)"))
    }

    /// Tasks about the participant, latest due first, one page at a time. Without `viewAll` the
    /// server leaves out completed and deleted tasks but still returns closed ones.
    public func participantTasks(
        id: Int,
        page: Int,
        pageSize: Int = APIClient.participantTaskPageSize
    ) async throws -> ParticipantTasksResponse {
        let query = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
            URLQueryItem(name: "viewAll", value: "false"),
        ]
        return try await decode(APIRequest(.get, "api/tasks/participant/\(id)", query: query))
    }

    /// Whether the caller's own profile change for this participant waits on approval (web
    /// "Update Pending").
    public func participantChangePending(userId: String, participantId: Int) async throws -> Bool {
        try await enveloped(
            APIRequest(.get, "api/employee/\(escape(userId))/\(participantId)/profile-change/last/is-Pending")
        )
    }
}
