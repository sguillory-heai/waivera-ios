/// Category tint of an icon tile. One meaning per tint, the same on every screen (Android UI8-11):
///
/// - `brand`: conversations, people and the app itself (settings, account, theme).
/// - `rose`: things about you: mentions, reactions, bookmarks, and how the app feels.
/// - `amber`: celebrations, announcements and notifications.
/// - `teal`: the schedule, whatever the timing: items, events, invitations, time off.
/// - `neutral`: read, past or inactive items, files, and a quiet "didn't load" line.
/// - `danger`: something that went wrong that you can act on (a message that wasn't sent).
/// - `celebration`: the emoji tile on a celebration; soft gold in light, warm plum in dark.
public enum TileTone: String, CaseIterable, Sendable {
    case brand
    case rose
    case amber
    case teal
    case neutral
    case danger
    case celebration

    /// The soft tile behind the glyph.
    public func container(isDark: Bool) -> RGBColor {
        RGBColor(hex: isDark ? hex.darkContainer : hex.lightContainer)
    }

    /// The outlined glyph on the tile (at least 4.5:1 on its container).
    public func content(isDark: Bool) -> RGBColor {
        RGBColor(hex: isDark ? hex.darkContent : hex.lightContent)
    }

    private var hex: ToneHexes {
        switch self {
        case .brand: ToneHexes(0xEEE7FB, BrandPalette.violet, 0x2E2448, BrandPalette.violetDarkLink)
        case .rose: ToneHexes(0xFBE6F1, 0xB4307D, 0x3A1A33, 0xFF8CC8)
        case .amber: ToneHexes(0xFFF1D6, 0x8A5600, 0x3D2A2A, 0xFFD27A)
        case .teal: ToneHexes(0xDDF4EF, 0x0A6B60, 0x133430, 0x6EE0CB)
        case .neutral: ToneHexes(0xEEE9F4, 0x5B5169, 0x2A2434, 0xB3A9C4)
        case .danger: ToneHexes(0xFCE8EC, 0xBE2E46, 0x3A1A24, 0xFF8A9B)
        case .celebration: ToneHexes(0xFFF1D6, 0x8A5600, 0x3A2533, 0xFFD27A)
        }
    }
}

/// A tile tone's four colours, in the order the palette table lists them.
private struct ToneHexes {
    let lightContainer: UInt32
    let lightContent: UInt32
    let darkContainer: UInt32
    let darkContent: UInt32

    init(_ lightContainer: UInt32, _ lightContent: UInt32, _ darkContainer: UInt32, _ darkContent: UInt32) {
        self.lightContainer = lightContainer
        self.lightContent = lightContent
        self.darkContainer = darkContainer
        self.darkContent = darkContent
    }
}

/// What a count is for (v5 decision 6): `attention` is something waiting on the person (unread,
/// Needs you), solid rose with white; `info` is a plain total, a neutral chip.
public enum CountTone: Sendable {
    case attention
    case info

    public var fill: ColorToken {
        switch self {
        case .attention: .unread
        case .info: .chipNeutral
        }
    }

    public var ink: ColorToken {
        switch self {
        case .attention: .onAccent
        case .info: .textSecondary
        }
    }
}

/// A status label's tone and its container and ink roles.
public enum StatusTone: Sendable {
    case neutral
    case accent
    case success
    case warning
    case danger

    public var container: ColorToken {
        switch self {
        case .neutral: .surfaceMuted
        case .accent: .accentSoft
        case .success: .milestoneBadgeAnniversary
        case .warning: .warningContainer
        case .danger: .dangerContainer
        }
    }

    public var ink: ColorToken {
        switch self {
        case .neutral: .textSecondary
        case .accent: .onAccentSoft
        case .success: .milestoneBadgeAnniversaryText
        case .warning: .onWarningContainer
        case .danger: .onDangerContainer
        }
    }
}
