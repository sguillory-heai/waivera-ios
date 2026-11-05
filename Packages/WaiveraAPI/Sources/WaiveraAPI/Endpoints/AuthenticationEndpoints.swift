import Foundation

/// `api/Authentication/*` and `api/users/*`.
extension APIClient {
    /// `GET /api/Authentication/login` — enveloped (gap G-02). Not a token exchange: it maps
    /// the Firebase identity to the Waivera user id and returns the two gate flags.
    public func login() async throws -> UserLoginResponseDto {
        try await enveloped(APIRequest(.get, "api/Authentication/login"))
    }

    public func userDetails(userId: String) async throws -> UserWithRoleDto {
        try await enveloped(APIRequest(.get, "api/Authentication/GetUserDetailsByUserID/\(escape(userId))"))
    }

    /// `GET /api/users/organization` — bare payload; 404 when the user has none.
    public func currentOrganization() async throws -> OrganizationResponse {
        try await decode(APIRequest(.get, "api/users/organization"))
    }

    /// 404 when the list is empty (not a 200 with `[]`), mapped here to `[]`.
    public func organizationDetails() async throws -> [OrganizationDto] {
        do {
            return try await envelopedIfPresent(APIRequest(.get, "api/Authentication/OrganizationDetails")) ?? []
        } catch WaiveraError.notFound {
            return []
        }
    }

    /// `GET /api/users`, bare: the caller's own organization plus their caseload participants,
    /// the list the web chat uses. The staff directory must come from here, never from
    /// `get-username-list`, which lists every organization's staff.
    public func organizationUsers(onlyActive: Bool = true) async throws -> [UserInfoResponse] {
        let request = APIRequest(
            .get,
            "api/users",
            query: [URLQueryItem(name: "onlyActive", value: onlyActive ? "true" : "false")]
        )
        // An empty body (a 204) is no users, not a failure.
        let data = try await send(request)
        guard !data.isEmpty else { return [] }
        return try Self.decodeBody(LossyArray<UserInfoResponse>.self, from: data).elements
    }

    /// Includes waiver participants; the staff apps use `organizationUsers()` instead (11 §1.4).
    public func combinedUserList() async throws -> [GetUserNameResponseDBVM] {
        try await envelopedIfPresent(APIRequest(.get, "api/Authentication/get-combined-user-list")) ?? []
    }

    public func updateContactAndTimezone(userId: String, _ body: UpdateContactAndTimezoneRequest) async throws {
        try await send(.json(.put, "api/Authentication/\(escape(userId))/UpdateContactAndTimezone", body: body))
    }

    /// Changes the password server-side: Firebase and `LastChangedPassword` together, which also
    /// clears the expiry gate. 400 is the password policy, 401 a sign-in that is not recent
    /// enough. Firebase then ends every existing session, so the caller signs in again.
    public func changePassword(_ body: ChangePasswordRequest) async throws {
        var request = try APIRequest.json(.post, "api/Authentication/change-password", body: body)
        // Its 401 means "verify your current password again", not a revoked account.
        request.reportsRejection = false
        try await send(request)
    }

    func escape(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? segment
    }
}
