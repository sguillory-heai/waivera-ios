import Foundation

/// Submitting, approving and rejecting a task, with the steps the web runs on the way
/// (sprout_web `TaskPage.HandleApprove`): the late reason and its review, unfinished forms, the
/// employee closure choice and the stage's own requirements.
extension APIClient {
    /// The refusals of an approval that say what to do next.
    public static let approvalRefusalStatuses: Set<Int> = [409, 422]

    /// `mode` is `CurrentStage` or `AllRemaining`.
    public func approvalRequirements(taskId: Int, mode: String) async throws -> ApprovalRequirementsResponse {
        try await decode(
            APIRequest(
                .get,
                "api/workflow/task/\(taskId)/approval-requirements",
                query: [URLQueryItem(name: "mode", value: mode)]
            )
        )
    }

    /// A 409/422 refusal comes back as its `ApprovalErrorResponse`; anything else not 2xx throws.
    public func approve(taskId: Int, _ body: ApproveTaskStageBody) async throws -> ApprovalAnswer {
        let (data, status) = try await sendAccepting(
            try .json(.post, "api/workflow/approve/\(taskId)", body: body),
            statuses: Self.approvalRefusalStatuses
        )
        guard Self.approvalRefusalStatuses.contains(status) else {
            let result = data.isEmpty ? nil : try? Self.decodeBody(ApprovalResultResponse.self, from: data)
            return .approved(completed: result?.taskCompleted == true)
        }
        return .refused(try? Self.decodeBody(ApprovalErrorResponse.self, from: data))
    }

    /// 404 means there is no earlier step to send it back to.
    public func rejectOptions(taskId: Int) async throws -> [RejectOptionResponse] {
        try await decode(
            APIRequest(.get, "api/workflow/task/\(taskId)/reject-options"),
            as: LossyArray<RejectOptionResponse>.self
        ).elements
    }

    /// The envelope can say no inside a 200; that throws too.
    public func reject(taskId: Int, _ body: RejectTaskBody) async throws {
        let data = try await sendKeepingCode(try .json(.post, "api/workflow/reject/\(taskId)", body: body))
        guard !data.isEmpty, let envelope = try? WaiveraJSON.decoder().decode(JSONValue.self, from: data) else {
            return
        }
        if case .bool(false) = envelope["success"] {
            let code: String? = if case .string(let value) = envelope["errorCode"] { value } else { nil }
            throw CodedRefusal(error: .invalidRequest, code: code)
        }
    }

    public func formDrafts(taskId: Int) async throws -> [TaskFormDraftResponse] {
        try await decode(
            APIRequest(.get, "api/form/v2/task/\(taskId)/drafts"),
            as: LossyArray<TaskFormDraftResponse>.self
        ).elements
    }

    public func employeeClosureOptions(taskId: Int) async throws -> EmployeeClosureOptionsResponse {
        try await decode(APIRequest(.get, "api/tasks/\(taskId)/employee-closure-options"))
    }

    public func employeeClosureChoice(taskId: Int, _ body: EmployeeClosureBody) async throws {
        try await send(try .json(.put, "api/tasks/\(taskId)/employee-closure-choice", body: body))
    }

    public func lateContext(taskId: Int) async throws -> LateContextResponse {
        try await decode(APIRequest(.get, "api/tasks/\(taskId)/justifications/context"))
    }

    public func justify(taskId: Int, _ body: LateJustificationBody) async throws {
        try await send(try .json(.post, "api/tasks/\(taskId)/justifications", body: body))
    }

    public func reviewJustification(taskId: Int, adjustmentId: Int64, _ body: LateReviewBody) async throws {
        try await send(try .json(.post, "api/tasks/\(taskId)/justifications/\(adjustmentId)/reviews", body: body))
    }

    /// The web's `uploadComplianceEvidence`; a refusal keeps its `errorCode` (`CodedRefusal`).
    public func uploadEvidence(_ form: EvidenceUploadForm) async throws -> EvidenceUploadResponse {
        let boundary = "waivera-\(UUID().uuidString)"
        let request = APIRequest(
            .post,
            "api/file/upload-compliance-evidence",
            body: form.multipartBody(boundary: boundary),
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        let data = try await sendKeepingCode(request)
        return try Self.decodeBody(EvidenceUploadResponse.self, from: data)
    }
}

/// What `approve` heard back: done, or a refusal whose body (when readable) says why.
public enum ApprovalAnswer: Sendable, Hashable {
    case approved(completed: Bool)
    case refused(ApprovalErrorResponse?)
}
