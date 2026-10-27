import Foundation

/// Screens shown before the tab shell (driven by session state, not by URLs).
public enum GateScreen: String, CaseIterable, Sendable {
    case loading
    case signIn = "sign-in"
    /// Firebase is signed in but the backend login failed; Retry or Sign out.
    case bootstrapFailed = "bootstrap-failed"
    /// The build has no API base URL or Firebase key (`Config/*.xcconfig`).
    case configurationMissing = "configuration-missing"
    case passwordChange = "password-change"
    case onboardingRequired = "onboarding-required"
    case notificationPrimer = "notification-primer"
}

/// Every screen the app can show, by a stable name. The DEBUG-only `-WaiveraRoute <name>`
/// launch argument and the `ScreenshotTour` UI test both use these names, so screenshots are
/// named `<name>__<variant>`. Ids match the shared fixtures served by the fake server.
public struct RouteCatalogEntry: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        case gate(GateScreen)
        case link(String)
    }

    public let name: String
    public let target: Target

    public init(name: String, target: Target) {
        self.name = name
        self.target = target
    }

    /// The destination for `.link` entries.
    public var destination: Destination? {
        guard case .link(let link) = target, let url = URL(string: link) else { return nil }
        return DeepLink.destination(from: url)
    }
}

public enum RouteCatalog {
    public static let all: [RouteCatalogEntry] = gates + links

    public static let gates: [RouteCatalogEntry] = GateScreen.allCases.map {
        RouteCatalogEntry(name: $0.rawValue, target: .gate($0))
    }

    public static let links: [RouteCatalogEntry] = [
        ("today", "waivera://today"),
        ("activity", "waivera://activity"),
        ("chat", "waivera://chats"),
        ("chat-new", "waivera://chats/new"),
        ("conversation", "waivera://chats/7"),
        ("conversation-target", "waivera://chats/7?messageId=9312"),
        ("thread", "waivera://chats/thread/9330?conversationId=7"),
        ("schedule", "waivera://schedule"),
        ("calendar-event", "waivera://calendar/evt_8f2b19c4"),
        ("profile", "waivera://profile"),
        ("organization", "waivera://profile/organization"),
        ("people", "waivera://people"),
        ("person", "waivera://people/usr_priya_raman"),
        ("bookmarks", "waivera://bookmarks"),
        ("settings", "waivera://settings"),
        ("settings-notifications", "waivera://settings/notifications"),
        ("settings-appearance", "waivera://settings/appearance"),
        ("settings-account", "waivera://settings/account"),
    ].map { RouteCatalogEntry(name: $0.0, target: .link($0.1)) }

    public static func entry(named name: String) -> RouteCatalogEntry? {
        all.first { $0.name == name }
    }
}
