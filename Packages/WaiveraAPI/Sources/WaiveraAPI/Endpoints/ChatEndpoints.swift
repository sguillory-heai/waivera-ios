import Foundation

/// `api/chat/*` (rest.md §2). Reactions have no REST route (gap G-01): use the hub.
extension APIClient {
    /// The fixed page size for history (gap G-06).
    public static let messagePageSize = 50

    /// `GET /api/chat/all` with both flags explicit (gap G-13). Includes channels.
    public func allConversations(includeArchived: Bool = false) async throws -> [ConversationResponse] {
        let request = APIRequest(
            .get,
            "api/chat/all",
            query: [
                URLQueryItem(name: "includeMeetings", value: "false"),
                URLQueryItem(name: "includeArchived", value: includeArchived ? "true" : "false"),
            ]
        )
        let rows: LossyArray<ConversationResponse>? = try await envelopedIfPresent(request)
        return rows?.elements ?? []
    }

    /// `GET /api/chat/my-conversations` — DMs and groups only, bare array.
    public func myConversations(includeMeetings: Bool = true) async throws -> [ConversationResponse] {
        let request = APIRequest(
            .get,
            "api/chat/my-conversations",
            query: [
                URLQueryItem(name: "includeMeetings", value: includeMeetings ? "true" : "false")
            ]
        )
        return try await decode(request, as: LossyArray<ConversationResponse>.self).elements
    }

    /// `GET /api/chat/conversation/{id}`. `unreadCount` is always 0 here (gap G-14).
    public func conversation(id: Int) async throws -> ConversationResponse {
        try await decode(APIRequest(.get, "api/chat/conversation/\(id)"))
    }

    /// One page, oldest first, no envelope (gap G-06).
    public func messagesPage(
        conversationId: Int,
        beforeMessageId: Int? = nil,
        pageSize: Int = APIClient.messagePageSize
    ) async throws -> [MessageSendResponse] {
        var query = [URLQueryItem(name: "pageSize", value: String(pageSize))]
        if let beforeMessageId {
            query.append(URLQueryItem(name: "beforeMessageId", value: String(beforeMessageId)))
        }
        let request = APIRequest(.get, "api/chat/\(conversationId)/messages/pagination", query: query)
        return try await decode(request, as: LossyArray<MessageSendResponse>.self).elements
    }

    /// Ascending, including the root message itself.
    public func thread(rootMessageId: Int) async throws -> [MessageSendResponse] {
        try await decode(APIRequest(.get, "api/chat/thread/\(rootMessageId)"), as: LossyArray<MessageSendResponse>.self)
            .elements
    }

    /// The REST send path, used when the hub is not connected. Idempotent on `clientMessageId`.
    public func sendMessage(_ body: SendMessageRequest) async throws -> MessageSendResponse {
        try await decode(.json(.post, "api/chat/send", body: body))
    }

    /// Returns the conversation; an existing one comes back with 200 and "already exists".
    public func createConversation(participantIds: [String]) async throws -> ConversationResponse {
        let body = CreateConversationRequest(participantIds: Array(Set(participantIds)).sorted())
        return try await enveloped(.json(.post, "api/chat/create-conversation", body: body))
    }

    public func markAsRead(conversationId: Int) async throws {
        try await send(APIRequest(.post, "api/chat/\(conversationId)/mark-as-read"))
    }

    public func readThrough(conversationId: Int, _ body: ChatReadThroughRequest) async throws -> ChatReadState {
        try await decode(.json(.put, "api/chat/\(conversationId)/read-through", body: body))
    }

    public func recentActivity(page: Int, pageSize: Int) async throws -> [ChatActivityResponse] {
        let request = APIRequest(
            .get,
            "api/chat/recent-activity",
            query: [
                URLQueryItem(name: "page", value: String(max(1, page))),
                URLQueryItem(name: "pageSize", value: String(min(100, max(1, pageSize)))),
            ]
        )
        return try await decode(request, as: LossyArray<ChatActivityResponse>.self).elements
    }

    public func markActivityRead(activityId: Int64) async throws {
        try await send(APIRequest(.put, "api/chat/recent-activity/\(activityId)/read"))
    }

    public func markActivityRead(messageId: Int) async throws {
        try await send(APIRequest(.put, "api/chat/recent-activity/message/\(messageId)/read"))
    }

    public func markAllActivityRead() async throws {
        try await send(APIRequest(.put, "api/chat/recent-activity/read-all"))
    }

    public func editMessage(messageId: Int, _ body: EditMessageRequest) async throws -> MessageSendResponse {
        try await enveloped(.json(.put, "api/chat/message/\(messageId)", body: body))
    }

    public func deleteMessage(messageId: Int) async throws -> MessageSendResponse? {
        try await envelopedIfPresent(APIRequest(.delete, "api/chat/message/\(messageId)"))
    }

    /// Toggles and returns the **new** bookmarked state.
    public func toggleBookmark(messageId: Int) async throws -> Bool {
        try await enveloped(APIRequest(.post, "api/chat/message/\(messageId)/bookmark"))
    }

    /// Known to 500 on bot rows (gap G-04); callers fall back to per-conversation search.
    public func bookmarks() async throws -> [MessageSendResponse] {
        let rows: LossyArray<MessageSendResponse>? = try await envelopedIfPresent(
            APIRequest(.get, "api/chat/bookmarks")
        )
        return rows?.elements ?? []
    }

    public func bookmarks(conversationId: Int) async throws -> [MessageSendResponse] {
        let request = APIRequest(.get, "api/chat/conversation/\(conversationId)/bookmarks")
        let rows: LossyArray<MessageSendResponse>? = try await envelopedIfPresent(request)
        return rows?.elements ?? []
    }

    public func searchConversation(_ conversationId: Int, query: ChatSearchQuery) async throws -> [MessageSendResponse]
    {
        let request = APIRequest(.get, "api/chat/search/conversation/\(conversationId)", query: query.queryItems)
        let rows: LossyArray<MessageSendResponse>? = try await envelopedIfPresent(request)
        return rows?.elements ?? []
    }

    /// `GET /api/chat/privatechats/{userId}/conversation`; `data == null` on a 200 is a failure.
    public func privateConversation(with userId: String) async throws -> ConversationResponse {
        try await enveloped(APIRequest(.get, "api/chat/privatechats/\(escape(userId))/conversation"))
    }

    public func conversationForEvent(calendarEventId: String) async throws -> ConversationResponse {
        try await enveloped(APIRequest(.get, "api/chat/getorcreate/conversationforEvent/\(escape(calendarEventId))"))
    }

    /// "Leave conversation" from the client's point of view.
    public func leaveConversation(conversationId: Int) async throws {
        try await send(APIRequest(.delete, "api/chat/delete/conversation/\(conversationId)"))
    }

    /// Multipart upload with a single part named `file` (11 §3.33).
    public func uploadAttachment(_ file: MultipartFile) async throws -> ChatAttachmentUploadResponse {
        let boundary = "waivera-\(UUID().uuidString)"
        let request = APIRequest(
            .post,
            "api/chat/upload-attachment",
            body: file.multipartBody(boundary: boundary),
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        let response: ChatAttachmentUploadResponse
        do {
            response = try await decode(request)
        } catch WaiveraError.invalidRequest, WaiveraError.server {
            throw WaiveraError.attachmentUploadFailed
        }
        guard !response.documentUrl.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw WaiveraError.attachmentUploadFailed
        }
        return response
    }

    /// The attachment bytes; `423` maps to `.attachmentBlocked` (gap G-15).
    public func attachmentData(messageId: Int) async throws -> Data {
        try await send(APIRequest(.get, "api/chat/message/\(messageId)/attachment", accept: "*/*"))
    }

    public func avatar(userId: String) async throws -> Base64AvatarResultDto {
        try await decode(APIRequest(.get, "api/file/avatar/\(escape(userId))"))
    }
}

/// Query for `GET /api/chat/search/conversation/{id}`.
public struct ChatSearchQuery: Sendable, Equatable {
    public var text: String?
    public var bookmarkedOnly = false
    public var includeThreads = true
    public var pageIndex = 1
    public var pageSize = 50

    public init(text: String? = nil, bookmarkedOnly: Bool = false, pageIndex: Int = 1, pageSize: Int = 50) {
        self.text = text
        self.bookmarkedOnly = bookmarkedOnly
        self.pageIndex = pageIndex
        self.pageSize = pageSize
    }

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "bookmarkedOnly", value: bookmarkedOnly ? "true" : "false"),
            URLQueryItem(name: "includeThreads", value: includeThreads ? "true" : "false"),
            URLQueryItem(name: "pageIndex", value: String(pageIndex)),
            URLQueryItem(name: "pageSize", value: String(pageSize)),
        ]
        if let text, !text.isEmpty { items.insert(URLQueryItem(name: "query", value: text), at: 0) }
        return items
    }
}

/// A file for a multipart upload. `data` is read by the caller (streamed from disk on
/// iOS by `AttachmentsRepository`), never base64-encoded.
public struct MultipartFile: Sendable, Equatable {
    public var data: Data
    public var fileName: String
    public var mimeType: String

    public init(data: Data, fileName: String, mimeType: String) {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }

    func multipartBody(boundary: String) -> Data {
        let safeName = fileName.replacingOccurrences(of: "\"", with: "'")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}
