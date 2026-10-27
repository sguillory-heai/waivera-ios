import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends authenticated requests to sprout_api. Adds the Firebase ID token as a
/// bearer token and retries once with a refreshed token on 401, matching the
/// Expo app's API client.
public struct APIClient: Sendable {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let tokens: any AuthTokenProvider

    public init(baseURL: URL, transport: any HTTPTransport = URLSession.shared, tokens: any AuthTokenProvider) {
        self.baseURL = baseURL
        self.transport = transport
        self.tokens = tokens
    }

    /// Posts `body` as JSON to `path` and ignores the response body.
    public func post(_ path: String, body: some Encodable & Sendable) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try WaiveraJSON.encoder().encode(body)
        _ = try await send(request)
    }

    func send(_ request: URLRequest) async throws -> Data {
        let token = try await tokens.idToken(forceRefresh: false)
        var (data, response) = try await transport.send(request.withBearer(token))

        if response.statusCode == 401, token != nil,
           let refreshed = try await tokens.idToken(forceRefresh: true) {
            (data, response) = try await transport.send(request.withBearer(refreshed))
        }

        switch response.statusCode {
        case 200..<300:
            return data
        case 401:
            throw WaiveraError.unauthorized
        default:
            throw WaiveraError.server(statusCode: response.statusCode)
        }
    }
}

private extension URLRequest {
    func withBearer(_ token: String?) -> URLRequest {
        guard let token else { return self }
        var copy = self
        copy.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return copy
    }
}
