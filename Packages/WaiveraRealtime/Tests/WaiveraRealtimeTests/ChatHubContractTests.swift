import Testing

@testable import WaiveraRealtime

struct ChatHubContractTests {
    // sprout_api maps the hub with `endpoints.MapHub<ChatHub>("api/chatHub")`.
    @Test func hubPathMatchesSproutAPI() {
        #expect(ChatHubContract.path == "api/chatHub")
    }
}
