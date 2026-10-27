import Foundation
import Testing

@testable import WaiveraAPI

struct ConfigurationTests {
    private let key = "test-key"

    @Test func httpsValuesLoad() throws {
        let result = WaiveraConfiguration.load(from: [
            "WaiveraAPIBaseURL": "https://api.example.test",
            "WaiveraFirebaseAPIKey": key,
            "WaiveraWebBaseURL": "https://app.example.test",
        ])
        let configuration = try result.get()
        #expect(configuration.apiBaseURL.absoluteString == "https://api.example.test")
        #expect(configuration.webBaseURL?.absoluteString == "https://app.example.test")
    }

    @Test func cleartextOrUnexpandedValuesCountAsMissing() {
        for base in ["http://api.example.test", "$(WAIVERA_API_BASE_URL)", "", "ftp://api.example.test", "https://"] {
            let result = WaiveraConfiguration.load(from: ["WaiveraAPIBaseURL": base, "WaiveraFirebaseAPIKey": key])
            #expect(result == .failure(MissingConfiguration(keys: [.apiBaseURL])), "\(base)")
        }
    }

    @Test func aCleartextWebBaseIsDropped() throws {
        let configuration = try WaiveraConfiguration.load(from: [
            "WaiveraAPIBaseURL": "https://api.example.test",
            "WaiveraFirebaseAPIKey": key,
            "WaiveraWebBaseURL": "http://app.example.test",
        ]).get()
        #expect(configuration.webBaseURL == nil)
    }
}
