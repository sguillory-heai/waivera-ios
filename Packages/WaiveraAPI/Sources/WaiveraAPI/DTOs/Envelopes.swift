/// Mirrors sprout_api `Utilities/ApiResponse<T>`. `data` is absent when null.
public struct ApiResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public var data: T?
    public var statusCode: Int?
    public var message: String?
    public var errorCode: String?
    public var success: Bool?
}

/// Mirrors sprout_api `Utilities/PagedResponse<T>`.
public struct PagedResponse<T: Codable & Sendable>: Codable, Sendable {
    public var data: [T]
    public var totalRecords: Int?
    public var pageNumber: Int?
    public var pageSize: Int?
}

/// The `{ items, totalRecords, pageNumber, pageSize }` page used by employee files.
public struct ItemsPage<T: Codable & Sendable>: Codable, Sendable {
    public var items: [T]
    public var totalRecords: Int?
    public var pageNumber: Int?
    public var pageSize: Int?
}

/// `{ "success": bool, "message": string? }` from `MobilePushController`.
public struct SuccessResponse: Codable, Sendable, Equatable {
    public var success: Bool
    public var message: String?
}
