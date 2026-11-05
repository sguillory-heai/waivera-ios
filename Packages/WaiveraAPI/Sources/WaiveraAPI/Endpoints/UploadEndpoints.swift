import Foundation

/// Files going onto tasks: the required files still missing, file templates, employee file
/// categories, and sprout_web's `uploadRequiredFile` (`FileController.cs`).
extension APIClient {
    /// Access is checked per task (404 otherwise).
    public func requiredAttachments(taskId: Int) async throws -> [RequiredAttachmentResponse] {
        try await decode(
            APIRequest(.get, "api/tasks/requiredAttachments/\(taskId)"),
            as: LossyArray<RequiredAttachmentResponse>.self
        ).elements
    }

    public func templateFiles() async throws -> [TemplateFileResponse] {
        try await decode(APIRequest(.get, "api/file/templateFiles"), as: LossyArray<TemplateFileResponse>.self)
            .elements
    }

    public func documentCategories() async throws -> [DocumentCategoryResponse] {
        try await enveloped(
            APIRequest(.get, "api/documentCategory/getall"),
            as: LossyArray<DocumentCategoryResponse>.self
        ).elements
    }

    /// One file onto a task. The server checks edit access, a locked task (409), the type, size
    /// and requirement; a refusal keeps its `errorCode` (`CodedRefusal`) so the app can word it.
    public func uploadTaskFile(_ form: TaskUploadForm) async throws -> TaskUploadResponse {
        let boundary = "waivera-\(UUID().uuidString)"
        let request = APIRequest(
            .post,
            "api/file/upload",
            body: form.multipartBody(boundary: boundary),
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        let data = try await sendKeepingCode(request)
        if data.isEmpty { return TaskUploadResponse() }
        return (try? Self.decodeBody(TaskUploadResponse.self, from: data)) ?? TaskUploadResponse()
    }
}
