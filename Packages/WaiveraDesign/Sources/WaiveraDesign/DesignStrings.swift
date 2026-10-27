#if canImport(UIKit)
    import Foundation

    /// User-facing strings owned by the design system. Values live in `Localizable.strings`.
    enum DesignStrings {
        static var retry: String { String(localized: "design.retry", bundle: .module) }
        static var tapToRetry: String { String(localized: "design.sync.failed", bundle: .module) }
        static var sending: String { String(localized: "design.sync.pending", bundle: .module) }
        static var undo: String { String(localized: "design.undo", bundle: .module) }
        static var dismiss: String { String(localized: "design.dismiss", bundle: .module) }
        static var cancel: String { String(localized: "design.cancel", bundle: .module) }
        static var loading: String { String(localized: "design.loading", bundle: .module) }
        static var offline: String { String(localized: "design.banner.offline", bundle: .module) }
        static var reconnecting: String { String(localized: "design.banner.reconnecting", bundle: .module) }
        static var showPassword: String { String(localized: "design.field.showPassword", bundle: .module) }
        static var hidePassword: String { String(localized: "design.field.hidePassword", bundle: .module) }
        static var selected: String { String(localized: "design.selected", bundle: .module) }

        static func unreadCount(_ count: Int) -> String {
            String(localized: "design.badge.unread \(count)", bundle: .module)
        }
    }
#endif
