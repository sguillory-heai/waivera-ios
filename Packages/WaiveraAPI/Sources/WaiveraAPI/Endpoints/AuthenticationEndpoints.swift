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

    /// The staff directory. 204 (no `data`) means no users.
    public func usernameList() async throws -> [GetUserNameResponseVM] {
        let rows: LossyArray<GetUserNameResponseVM>? = try await envelopedIfPresent(
            APIRequest(.get, "api/Authentication/get-username-list")
        )
        return rows?.elements ?? []
    }

    /// Includes waiver participants; the staff apps use `usernameList()` instead (11 §1.4).
    public func combinedUserList() async throws -> [GetUserNameResponseDBVM] {
        try await envelopedIfPresent(APIRequest(.get, "api/Authentication/get-combined-user-list")) ?? []
    }

    public func updateContactAndTimezone(userId: String, _ body: UpdateContactAndTimezoneRequest) async throws {
        try await send(.json(.put, "api/Authentication/\(escape(userId))/UpdateContactAndTimezone", body: body))
    }

    /// Tells the backend the password was changed in Firebase, clearing the expiry gate.
    /// The request DTO is undocumented (01 §5); an empty body is sent.
    public func confirmPasswordChange() async throws {
        try await send(.json(.post, "api/Authentication/confirm-password-change", body: EmptyBody()))
    }

    func escape(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? segment
    }
}
