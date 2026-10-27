import Foundation
import Testing
import WaiveraFixtures

@testable import WaiveraAPI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Answers requests from a list of canned responses and records what was sent.
actor StubTransport: HTTPTransport {
    struct Reply: Sendable {
        var status: Int
        var body: Data

        static func json(_ text: String, status: Int = 200) -> Reply { Reply(status: status, body: Data(text.utf8)) }
        static func fixture(_ name: String, status: Int = 200) throws -> Reply {
            Reply(status: status, body: try Fixture.data(name))
        }
        static func empty(_ status: Int) -> Reply { Reply(status: status, body: Data()) }
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    private let failure: (any Error)?

    init(_ replies: [Reply] = [], failure: (any Error)? = nil) {
        self.replies = replies
        self.failure = failure
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let failure { throw failure }
        let reply = replies.isEmpty ? Reply.empty(200) : replies.removeFirst()
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)
        else { throw WaiveraError.invalidResponse }
        return (reply.body, response)
    }
}

struct FakeTokens: AuthTokenProvider {
    var signedIn = true

    func idToken(forceRefresh: Bool) async throws -> String? {
        guard signedIn else { return nil }
        return forceRefresh ? "refreshed" : "cached"
    }
}

/// A clock that only moves when told to.
final class ManualClock: WaiveraClock, @unchecked Sendable {
    private let value: LockedValue<Date>

    init(_ start: Date = Date(timeIntervalSince1970: 1_792_000_000)) {
        value = LockedValue(start)
    }

    var now: Date { value.get() }
    func advance(_ seconds: TimeInterval) { value.update { $0 = $0.addingTimeInterval(seconds) } }
    func sleep(for duration: Duration) async throws { await Task.yield() }
}

func makeClient(_ transport: StubTransport, tokens: any AuthTokenProvider = FakeTokens()) throws -> APIClient {
    APIClient(baseURL: try #require(URL(string: "https://api.example.test/")), transport: transport, tokens: tokens)
}

func decodeFixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try WaiveraJSON.decoder().decode(type, from: Fixture.data(name))
}

func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Double = 0) -> Date {
    let days = CalendarDate.daysFromCivil(year: year, month: month, day: day)
    return Date(timeIntervalSince1970: Double(days * 86_400 + hour * 3_600 + minute * 60) + second)
}
