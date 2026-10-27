/// Mirrors sprout_api `dto/Request/MobilePushRegistrationRequest`. Native apps always register FCM tokens.
public struct MobilePushRegistration: Encodable, Equatable, Sendable {
    public var deviceID: String
    public var pushToken: String
    public var platform = "ios"
    public var provider = "fcm"
    public var pushEnabled: Bool
    public var chatMessagesEnabled: Bool
    public var mentionsEnabled: Bool
    public var reactionsEnabled: Bool
    public var activeCallsEnabled: Bool
    public var soundEnabled: Bool
    public var vibrationEnabled: Bool
    public var previewContentEnabled: Bool

    public init(
        deviceID: String,
        pushToken: String,
        pushEnabled: Bool,
        chatMessagesEnabled: Bool,
        mentionsEnabled: Bool,
        reactionsEnabled: Bool,
        activeCallsEnabled: Bool,
        soundEnabled: Bool,
        vibrationEnabled: Bool,
        previewContentEnabled: Bool
    ) {
        self.deviceID = deviceID
        self.pushToken = pushToken
        self.pushEnabled = pushEnabled
        self.chatMessagesEnabled = chatMessagesEnabled
        self.mentionsEnabled = mentionsEnabled
        self.reactionsEnabled = reactionsEnabled
        self.activeCallsEnabled = activeCallsEnabled
        self.soundEnabled = soundEnabled
        self.vibrationEnabled = vibrationEnabled
        self.previewContentEnabled = previewContentEnabled
    }

    enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case pushToken, platform, provider, pushEnabled, chatMessagesEnabled, mentionsEnabled
        case reactionsEnabled, activeCallsEnabled, soundEnabled, vibrationEnabled, previewContentEnabled
    }
}

/// Mirrors sprout_api `MobilePushUnregisterRequest`.
public struct MobilePushUnregistration: Encodable, Equatable, Sendable {
    public var deviceID: String

    public init(deviceID: String) {
        self.deviceID = deviceID
    }

    enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
    }
}

/// `MobilePushController` routes (`api/mobile-push`).
public extension APIClient {
    func registerForPush(_ registration: MobilePushRegistration) async throws {
        try await post("api/mobile-push/register", body: registration)
    }

    func unregisterFromPush(deviceID: String) async throws {
        try await post("api/mobile-push/unregister", body: MobilePushUnregistration(deviceID: deviceID))
    }
}
