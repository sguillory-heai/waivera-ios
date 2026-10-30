import Foundation

/// Every non-2xx body shape sprout_api produces (gap G-12), reduced to what the client
/// may use internally. `serverMessage` is for classification only and is never shown.
public struct APIErrorBody: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        /// (a) no body at all (`Forbid()`, token middleware).
        case empty
        /// (b) a bare JSON string (`Unauthorized("No uid found in HttpContext.")`).
        case jsonString
        /// (c) `text/plain`.
        case plainText
        /// (d) camelCase `ApiResponse<T>`.
        case apiResponse
        /// (e) PascalCase `ApiResponse<T>` from `ExceptionMiddleware`.
        case pascalCaseApiResponse
        /// (f) `{ "success": false, "message": "…" }` from `MobilePushController`.
        case successMessage
        /// A JSON object we do not recognise.
        case unknownObject
    }

    public let shape: Shape
    public let serverMessage: String?
    public let errorCode: String?

    public init(data: Data) {
        guard let decoded = String(bytes: data, encoding: .utf8) else {
            // Not text at all: keep it out of user-facing messages.
            self.init(shape: .plainText, serverMessage: nil, errorCode: nil)
            return
        }
        let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            self.init(shape: .empty, serverMessage: nil, errorCode: nil)
            return
        }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            self.init(shape: .plainText, serverMessage: text, errorCode: nil)
            return
        }
        switch json {
        case .string(let message):
            self.init(shape: .jsonString, serverMessage: message, errorCode: nil)
        case .object(let object):
            self.init(object: object)
        default:
            self.init(shape: .unknownObject, serverMessage: nil, errorCode: nil)
        }
    }

    private init(object: [String: JSONValue]) {
        let isPascal = object.keys.contains { $0.first?.isUppercase == true }
        let normalized = Dictionary(object.map { (WaiveraJSON.camelCase($0.key), $0.value) }) { first, _ in first }
        let message =
            normalized["message"]?.stringValue
            ?? normalized["error"]?.stringValue
            ?? normalized["title"]?.stringValue
        let code = normalized["errorCode"]?.stringValue
        let shape: Shape
        if normalized["statusCode"] != nil {
            shape = isPascal ? .pascalCaseApiResponse : .apiResponse
        } else if normalized["success"] != nil {
            shape = .successMessage
        } else {
            shape = .unknownObject
        }
        self.init(shape: shape, serverMessage: message, errorCode: code)
    }

    init(shape: Shape, serverMessage: String?, errorCode: String?) {
        self.shape = shape
        self.serverMessage = serverMessage
        self.errorCode = errorCode
    }
}

/// Maps an HTTP status plus body to a `WaiveraError`, status first (gap G-12).
public enum APIErrorMapper {
    public static func map(statusCode: Int, body: Data) -> WaiveraError {
        let parsed = APIErrorBody(data: body)
        let hint = parsed.serverMessage?.lowercased() ?? ""
        switch statusCode {
        case 400:
            if hint.contains("attachment upload is missing") { return .attachmentUploadFailed }
            return .invalidRequest
        case 401:
            return .unauthorized
        case 403:
            if hint.contains("archived") { return .channelArchived }
            if hint.contains("read-only") || hint.contains("cannot post") { return .channelReadOnly }
            return .forbidden
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 423:
            return .attachmentBlocked
        default:
            return .server(statusCode: statusCode)
        }
    }
}
