import Foundation

/// What a Waivera link in a chat message points at, read the way the web's link previews read
/// it: `Controllers/Wiki/HelpController.cs` and `Controllers/ResourceChatController.cs`.
extension APIClient {
    /// Every published FAQ article the caller may open, by category.
    public func publishedFaqs() async throws -> [FaqCategoryListResponse] {
        let categories: LossyArray<FaqCategoryListResponse> = try await decode(APIRequest(.get, "api/help/faqs"))
        return categories.elements
    }

    /// A published resource; 404 when it is a draft or the caller may not see it.
    public func resourcePreview(id: String) async throws -> ResourceChatPreviewResponse {
        try await decode(APIRequest(.get, "api/resource-directory/chat/\(escape(id))"))
    }
}
