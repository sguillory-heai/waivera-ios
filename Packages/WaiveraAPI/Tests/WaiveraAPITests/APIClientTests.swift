import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import WaiveraAPI

struct APIClientTests {

    @Test func sendsTheBearerTokenAndJSONBody() async throws {
        let transport = RecordingTransport(statuses: [200])
        let client = try makeClient(transport)

        try await client.unregisterFromPush(deviceID: "device-1")

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.example.test/api/mobile-push/unregister")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer cached")
        #expect(request.httpBody == Data(#"{"deviceId":"device-1"}"#.utf8))
    }

    @Test func retriesOnceWithARefreshedTokenAfter401() async throws {
        let transport = RecordingTransport(statuses: [401, 200])
        let client = try makeClient(transport)

        try await client.unregisterFromPush(deviceID: "device-1")

        let tokens = await transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(tokens == ["Bearer cached", "Bearer refreshed"])
    }

    @Test func reportsUnauthorizedWhenTheRefreshedTokenIsAlsoRejected() async throws {
        let transport = RecordingTransport(statuses: [401, 401])
        let client = try makeClient(transport)

        await #expect(throws: WaiveraError.unauthorized) {
            try await client.unregisterFromPush(deviceID: "device-1")
        }
        #expect(await transport.requests.count == 2)
    }

    @Test func doesNotRetryWhenSignedOut() async throws {
        let transport = RecordingTransport(statuses: [401])
        let client = try makeClient(transport, tokens: FakeTokens(signedIn: false))

        await #expect(throws: WaiveraError.unauthorized) {
            try await client.unregisterFromPush(deviceID: "device-1")
        }
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func mapsServerErrorsWithoutLeakingTheBody() async throws {
        let transport = RecordingTransport(statuses: [500])
        let client = try makeClient(transport)

        await #expect(throws: WaiveraError.server(statusCode: 500)) {
            try await client.unregisterFromPush(deviceID: "device-1")
        }
    }

    private func makeClient(_ transport: RecordingTransport, tokens: FakeTokens = FakeTokens()) throws -> APIClient {
        APIClient(baseURL: try #require(URL(string: "https://api.example.test/")), transport: transport, tokens: tokens)
    }
}

private struct FakeTokens: AuthTokenProvider {
    var signedIn = true

    func idToken(forceRefresh: Bool) async throws -> String? {
        guard signedIn else { return nil }
        return forceRefresh ? "refreshed" : "cached"
    }
}

private actor RecordingTransport: HTTPTransport {
    private var statuses: [Int]
    private(set) var requests: [URLRequest] = []

    init(statuses: [Int]) {
        self.statuses = statuses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let status = statuses.isEmpty ? 200 : statuses.removeFirst()
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else { throw WaiveraError.invalidResponse }
        return (Data("server detail".utf8), response)
    }
}
