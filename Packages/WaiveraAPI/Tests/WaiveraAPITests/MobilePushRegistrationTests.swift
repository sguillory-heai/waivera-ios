import Foundation
import Testing
@testable import WaiveraAPI

struct MobilePushRegistrationTests {
    @Test func encodesTheSproutAPIFieldNamesWithFCMDefaults() throws {
        let registration = MobilePushRegistration(
            deviceID: "device-1",
            pushToken: "fcm-token",
            pushEnabled: true,
            chatMessagesEnabled: true,
            mentionsEnabled: true,
            reactionsEnabled: false,
            activeCallsEnabled: true,
            soundEnabled: false,
            vibrationEnabled: true,
            previewContentEnabled: false
        )

        let data = try WaiveraJSON.encoder().encode(registration)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["deviceId"] as? String == "device-1")
        #expect(json["pushToken"] as? String == "fcm-token")
        #expect(json["platform"] as? String == "ios")
        #expect(json["provider"] as? String == "fcm")
        #expect(json["previewContentEnabled"] as? Bool == false)
        #expect(json.count == 12)
    }
}
