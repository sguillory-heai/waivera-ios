import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// One sprout_api call, before auth is attached.
public struct APIRequest: Sendable {
    public var method: HTTPMethod
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    /// Only set for bodies; multipart uploads carry their own boundary (01 §4).
    public var contentType: String?
    public var accept: String
    public var requiresAuth: Bool

    public init(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        accept: String = "application/json",
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.contentType = contentType
        self.accept = accept
        self.requiresAuth = requiresAuth
    }

    public static func json(_ method: HTTPMethod, _ path: String, body: some Encodable) throws -> APIRequest {
        APIRequest(method, path, body: try WaiveraJSON.encoder().encode(body), contentType: "application/json")
    }
}

/// Tells the session that the server rejected a freshly refreshed token, which means the
/// account was revoked or disabled in sprout_api (IF-05, IS-06). Only that definitive case is
/// sent: rate limits, 5xx and network failures never are.
public final class SessionRejections: Sendable {
    private let broadcaster = AsyncBroadcaster<Int>(replays: false)
    private let count = LockedValue(0)

    public init() {}

    public func stream() -> AsyncStream<Int> { broadcaster.stream() }

    func send() {
        broadcaster.send(count.update { value -> Int in
            value += 1
            return value
        })
    }
}

/// Sends requests to sprout_api. Adds the Firebase ID token as a bearer token, retries
/// exactly once with a force-refreshed token on 401, and maps every failure to a
/// `WaiveraError` (all thrown errors are `WaiveraError`). A 401 that survives the refresh is
/// reported to `rejections`.
public struct APIClient: Sendable {
    public let baseURL: URL
    private let transport: any HTTPTransport
    private let tokens: any AuthTokenProvider
    public let rejections: SessionRejections

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSession.shared,
        tokens: any AuthTokenProvider,
        rejections: SessionRejections = SessionRejections()
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.tokens = tokens
        self.rejections = rejections
    }

    /// Absolute URL for an API path. Accepts the relative `attachmentUrl` form
    /// (`/api/chat/message/9320/attachment`) as well as `api/...`.
    public func url(for path: String, query: [URLQueryItem] = []) -> URL {
        let trimmed = String(path.drop { $0 == "/" })
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
        let joined = URL(string: base + trimmed) ?? baseURL
        guard !query.isEmpty, var components = URLComponents(url: joined, resolvingAgainstBaseURL: false) else {
            return joined
        }
        components.queryItems = (components.queryItems ?? []) + query
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? joined
    }

    /// Sends `request` and returns the body of a 2xx response.
    @discardableResult
    public func send(_ request: APIRequest) async throws -> Data {
        try await sendWithResponse(request).0
    }

    public func sendWithResponse(_ request: APIRequest) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = makeURLRequest(request)
        var token: String?
        if request.requiresAuth {
            token = try await currentToken(forceRefresh: false)
            guard token != nil else { throw WaiveraError.signedOut }
        }
        var (data, response) = try await perform(urlRequest.withBearer(token))
        if response.statusCode == 401, request.requiresAuth {
            guard let refreshed = try await currentToken(forceRefresh: true) else {
                throw WaiveraError.unauthorized
            }
            (data, response) = try await perform(urlRequest.withBearer(refreshed))
            if response.statusCode == 401 { rejections.send() }
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIErrorMapper.map(statusCode: response.statusCode, body: data)
        }
        return (data, response)
    }

    /// Decodes a bare (non-enveloped) body.
    public func decode<T: Decodable>(_ request: APIRequest, as type: T.Type = T.self) async throws -> T {
        let data = try await send(request)
        return try Self.decodeBody(type, from: data)
    }

    /// Decodes `ApiResponse<T>` and returns `data`, treating `data == nil` (including the
    /// `statusCode: 200, data: null` failure of `/privatechats`, gap G-12) as `.invalidResponse`.
    public func enveloped<T: Decodable & Sendable>(_ request: APIRequest, as type: T.Type = T.self) async throws -> T {
        guard let value = try await envelopedIfPresent(request, as: type) else {
            throw WaiveraError.invalidResponse
        }
        return value
    }

    /// Like `enveloped` but returns `nil` for an absent `data` (204 lists, empty bodies).
    public func envelopedIfPresent<T: Decodable & Sendable>(
        _ request: APIRequest,
        as type: T.Type = T.self
    ) async throws -> T? {
        let (data, response) = try await sendWithResponse(request)
        if response.statusCode == 204 || data.isEmpty { return nil }
        let envelope = try Self.decodeBody(ApiResponse<T>.self, from: data)
        if envelope.success == false { throw APIErrorMapper.map(statusCode: envelope.statusCode ?? 500, body: data) }
        return envelope.data
    }

    /// Builds an authorised `URLRequest` for loaders that fetch bytes themselves
    /// (attachment images, gap G-15). The caller owns the 401 retry by calling again with
    /// `forceRefresh: true`.
    public func authorizedURLRequest(for path: String, forceRefresh: Bool = false) async throws -> URLRequest {
        guard let token = try await currentToken(forceRefresh: forceRefresh) else { throw WaiveraError.signedOut }
        var request = URLRequest(url: url(for: path))
        request.httpMethod = HTTPMethod.get.rawValue
        return request.withBearer(token)
    }

    static func decodeBody<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try WaiveraJSON.decoder().decode(type, from: data)
        } catch {
            throw WaiveraError.invalidResponse
        }
    }

    private func makeURLRequest(_ request: APIRequest) -> URLRequest {
        var urlRequest = URLRequest(url: url(for: request.path, query: request.query))
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue(request.accept, forHTTPHeaderField: "Accept")
        if let contentType = request.contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        urlRequest.httpBody = request.body
        return urlRequest
    }

    private func currentToken(forceRefresh: Bool) async throws -> String? {
        do {
            return try await tokens.idToken(forceRefresh: forceRefresh)
        } catch {
            throw WaiveraError.from(error)
        }
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            throw WaiveraError.from(error)
        }
    }
}

extension URLRequest {
    func withBearer(_ token: String?) -> URLRequest {
        guard let token else { return self }
        var copy = self
        copy.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return copy
    }
}
