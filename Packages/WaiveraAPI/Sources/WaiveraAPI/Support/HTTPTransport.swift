import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The one place the API client touches the network, so tests can substitute a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WaiveraError.invalidResponse
        }
        return (data, http)
    }
}
