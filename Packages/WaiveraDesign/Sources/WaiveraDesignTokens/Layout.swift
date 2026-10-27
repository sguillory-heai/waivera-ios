import Foundation

/// Spacing scale. Layouts use these, never literal numbers. Values are points.
public enum Spacing {
    public static let hairline: CGFloat = 1
    public static let extraSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let smallPlus: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let mediumPlus: CGFloat = 20
    public static let large: CGFloat = 24
    public static let extraLarge: CGFloat = 32
    public static let huge: CGFloat = 48
}

/// Corner radii, from the recurring values in the Expo app (10-design-feedback §2).
public enum Radius {
    public static let chip: CGFloat = 8
    public static let button: CGFloat = 12
    public static let field: CGFloat = 12
    public static let card: CGFloat = 14
    public static let pill: CGFloat = 18
    public static let bubble: CGFloat = 20
    public static let sheet: CGFloat = 24
}

/// Fixed control sizes. Hit targets never drop below Apple's 44pt minimum even when the
/// visible glyph is smaller.
public enum ControlSize {
    public static let minHitTarget: CGFloat = 44
    public static let buttonHeight: CGFloat = 48
    public static let iconTile: CGFloat = 48
    public static let smallIcon: CGFloat = 20
    public static let avatarSmall: CGFloat = 28
    public static let avatarMedium: CGFloat = 44
    public static let avatarLarge: CGFloat = 88
    public static let milestoneRingWidth: CGFloat = 2
    public static let unreadDot: CGFloat = 10
    public static let badgeMinWidth: CGFloat = 20
    public static let skeletonLine: CGFloat = 14
}

/// Opacity steps for disabled and pressed states (PrimaryButton in 10-design-feedback §3).
public enum Emphasis {
    public static let disabled: Double = 0.5
    public static let pressed: Double = 0.82
}

/// Avatar geometry: radius is `max(8, round(size * 0.24))` unless the avatar is circular.
public enum AvatarGeometry {
    public static func cornerRadius(size: CGFloat, rounded: Bool) -> CGFloat {
        rounded ? size / 2 : max(8, (size * 0.24).rounded())
    }

    public static func fallbackGlyphSize(size: CGFloat) -> CGFloat {
        (size * 0.5).rounded()
    }

    /// Up to two initials from a display name, uppercased. Empty when nothing usable remains,
    /// in which case the view shows a person glyph.
    public static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" })
            .filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        guard let first = words.first?.first else { return "" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }
}

/// Count badges cap at `99+` (00-inventory §1).
public enum BadgeFormatter {
    public static let cap = 99

    /// `nil` hides the badge.
    public static func text(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > cap ? "\(cap)+" : String(count)
    }
}

/// Typography details that are not a text style.
public enum TypographyMetrics {
    /// Letter spacing for uppercase eyebrow labels.
    public static let eyebrowTracking: CGFloat = 1
}

/// Durations for transient feedback.
public enum FeedbackTiming {
    /// Undo toast lifetime.
    public static let undoToast: Double = 4
    /// Undo toast lifetime while VoiceOver runs, so the action can be reached.
    public static let undoToastAccessible: Double = 10
    /// In-app message banner lifetime (Expo `ChatMessageBanner`).
    public static let inAppBanner: Double = 4.5
    /// Short confirmation pill such as "Bookmark saved".
    public static let confirmationPill: Double = 1.8
}

extension SkeletonTiming {
    /// Time a shown skeleton must still stay up after loading ended, given how long it has been visible.
    public func remainingVisible(shownFor: Double) -> Double {
        max(0, minimumVisible - shownFor)
    }
}

/// Send/sync state of an optimistic item (message, status change).
public enum SyncState: Equatable, Sendable {
    case synced
    case pending
    case failed
}

extension Emphasis {
    /// Border alpha for tinted banners.
    public static let bannerBorder: Double = 0.4
    /// Fill alpha for tinted banners and icon tiles.
    public static let bannerWash: Double = 0.1
}
