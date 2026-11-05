import Foundation

/// Deciding every admin request type and asking for time off: `TimeOffController.cs`,
/// `AdmininistrativeTransactionController.cs` (profile changes), `LeaveManagementController.cs`
/// and `TrainingExternalController.cs`. The server re-checks who may decide each one.
extension APIClient {
    public func decideTimeOff(id: Int, _ body: RequestActionBody) async throws {
        try await checkEnvelope(try .json(.post, "api/TimeOff/approve-reject/\(id)", body: body))
    }

    /// Profile changes: the server applies the stored requested values itself.
    public func decideProfileChange(id: Int, _ body: RequestActionBody) async throws {
        try await checkEnvelope(try .json(.post, "api/admin/request/approve-reject/\(id)", body: body))
    }

    public func leaveBalances(employeeId: String) async throws -> LeaveBalancesResponse {
        let id = employeeId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? employeeId
        return try await enveloped(APIRequest(.get, "api/leave-management/employees/\(id)/balances"))
    }

    /// The agency's leave types, as a bare list.
    public func leaveTypes() async throws -> [LeaveTypeResponse] {
        try await decode(APIRequest(.get, "api/TimeOff/all"), as: LossyArray<LeaveTypeResponse>.self).elements
    }

    public func previewLeave(_ body: LeavePreviewBody) async throws -> LeavePreviewResponse {
        try await enveloped(try .json(.post, "api/leave-management/requests/preview", body: body))
    }

    /// A refusal throws `CodedRefusal`, so the app can word the ones the person can fix.
    public func requestTimeOff(_ body: TimeOffBody) async throws {
        let data = try await sendKeepingCode(try .json(.post, "api/TimeOff/add-update-timeOff", body: body))
        guard !data.isEmpty, let envelope = try? WaiveraJSON.decoder().decode(JSONValue.self, from: data) else {
            return
        }
        if case .bool(false) = envelope["success"] {
            let code: String? = if case .string(let value) = envelope["errorCode"] { value } else { nil }
            throw CodedRefusal(error: .invalidRequest, code: code)
        }
    }

    public func leaveSettings() async throws -> LeaveSettingsResponse {
        try await enveloped(APIRequest(.get, "api/leave-management/settings"))
    }

    public func trainingCredit(requestId: Int) async throws -> TrainingCreditResponse {
        try await decode(APIRequest(.get, "api/training/external/requests/\(requestId)"))
    }

    public func decideTrainingCredit(requestId: Int, _ body: TrainingDecisionBody) async throws {
        try await checkEnvelope(try .json(.post, "api/training/external/requests/\(requestId)/decision", body: body))
    }

    public func trainingCertificate(requestId: Int) async throws -> (Data, HTTPURLResponse) {
        try await sendWithResponse(APIRequest(.get, "api/training/external/requests/\(requestId)/certificate"))
    }
}
