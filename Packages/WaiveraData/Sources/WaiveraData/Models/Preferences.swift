import Foundation

/// Notification switches (08 §8). Server flags go out with every push registration; the
/// rest are applied on the device at presentation time (gap G-08).
public struct NotificationPreferences: Codable, Sendable, Hashable {
    public var pushEnabled = true
    public var chatMessages = true
    public var mentions = true
    public var reactions = true
    public var activeCalls = true
    /// Client-only: in-app banners for hub events.
    public var inAppBanners = true
    public var sound = true
    public var vibration = true
    public var previewContent = true

    public init() {}
}

public enum AppearancePreference: String, Codable, Sendable, Hashable, CaseIterable {
    case system, light, dark
}

/// Everything on the Settings screens that the device stores.
public struct AppSettings: Codable, Sendable, Hashable {
    public var notifications = NotificationPreferences()
    public var appearance = AppearancePreference.system
    /// The haptics switch from the UX feedback map.
    public var hapticsEnabled = true

    public init() {}
}
