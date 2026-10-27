import Foundation

/// An sRGB colour as plain data, so contrast and theme rules are testable without UIKit.
public struct RGBColor: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// `hex` is `0xRRGGBB`.
    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public func withAlpha(_ alpha: Double) -> RGBColor {
        RGBColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// WCAG 2.x relative luminance of the opaque colour.
    public var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.039_28 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two opaque colours (1...21).
    public func contrastRatio(against other: RGBColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// Every colour role in the app. Feature code reads these through `WaiveraDesign`; no literal colours.
/// Values come from `spec/features/10-design-feedback.md` §1 and match Android's `WaiveraColors`.
public enum ColorToken: String, CaseIterable, Sendable {
    case background
    case surface
    case surfaceMuted
    case border
    case text
    case textSecondary
    case accent
    case accentSoft
    /// Pressed or selected wash (Expo `accent + '14'`).
    case accentWash
    /// Own-bubble border (Expo `accent + '28'`).
    case accentBorder
    /// Linked-task border (Expo `accent + '35'`).
    case accentBorderStrong
    /// Label and spinner drawn on an `accent` fill.
    case onAccent
    /// Label drawn on a `danger` fill.
    case onDanger
    case danger
    case success
    case warning
    case unread
    /// Modal and sheet scrim.
    case scrim
    /// Switch thumb and other always-white details.
    case thumb
    case milestone
    case holiday
    case milestoneBadgeBirthday
    case milestoneBadgeBirthdayText
    case milestoneBadgeAnniversary
    case milestoneBadgeAnniversaryText
    case milestoneBadgeWelcome
    case milestoneBadgeWelcomeText

    public var light: RGBColor { values.light }
    public var dark: RGBColor { values.dark }

    public func value(isDark: Bool) -> RGBColor {
        isDark ? dark : light
    }

    // Each case is one table row; splitting the switch would hide the palette.
    // swiftlint:disable:next cyclomatic_complexity
    private var values: (light: RGBColor, dark: RGBColor) {
        switch self {
        case .background: (RGBColor(hex: 0xF8F9FA), RGBColor(hex: 0x0F0F12))
        case .surface: (RGBColor(hex: 0xFFFFFF), RGBColor(hex: 0x1F2937))
        case .surfaceMuted: (RGBColor(hex: 0xF3F4F6), RGBColor(hex: 0x111827))
        case .border: (RGBColor(hex: 0xE5E7EB), RGBColor(hex: 0x374151))
        case .text: (RGBColor(hex: 0x111827), RGBColor(hex: 0xF9FAFB))
        case .textSecondary: (RGBColor(hex: 0x6B7280), RGBColor(hex: 0x9CA3AF))
        case .accent, .unread: (RGBColor(hex: 0x7E57C2), RGBColor(hex: 0xA78BFA))
        case .accentSoft: (RGBColor(hex: 0xEEE7F8), RGBColor(hex: 0x2C2340))
        case .accentWash: (RGBColor(hex: 0x7E57C2, alpha: 0.08), RGBColor(hex: 0xA78BFA, alpha: 0.08))
        case .accentBorder: (RGBColor(hex: 0x7E57C2, alpha: 0.16), RGBColor(hex: 0xA78BFA, alpha: 0.16))
        case .accentBorderStrong: (RGBColor(hex: 0x7E57C2, alpha: 0.21), RGBColor(hex: 0xA78BFA, alpha: 0.21))
        // #A78BFA is light enough that a near-black label reads better than white in dark mode.
        case .onAccent: (RGBColor(hex: 0xFFFFFF), RGBColor(hex: 0x0F0F12))
        case .onDanger: (RGBColor(hex: 0xFFFFFF), RGBColor(hex: 0x0F0F12))
        // Light danger is darkened from #EF4444 so white labels pass 4.5:1.
        case .danger: (RGBColor(hex: 0xDC2626), RGBColor(hex: 0xF87171))
        case .success: (RGBColor(hex: 0x16A34A), RGBColor(hex: 0x4ADE80))
        case .warning: (RGBColor(hex: 0xD97706), RGBColor(hex: 0xFBBF24))
        case .scrim: (RGBColor(hex: 0x000000, alpha: 0.36), RGBColor(hex: 0x000000, alpha: 0.36))
        case .thumb: (RGBColor(hex: 0xFFFFFF), RGBColor(hex: 0xFFFFFF))
        case .milestone: (RGBColor(hex: 0xF59E0B), RGBColor(hex: 0xFBBF24))
        case .holiday: (RGBColor(hex: 0x8B5CF6), RGBColor(hex: 0xA78BFA))
        case .milestoneBadgeBirthday: (RGBColor(hex: 0xFEF3C7), RGBColor(hex: 0x3B2F0B))
        case .milestoneBadgeBirthdayText: (RGBColor(hex: 0x92400E), RGBColor(hex: 0xFDE68A))
        case .milestoneBadgeAnniversary: (RGBColor(hex: 0xD1FAE5), RGBColor(hex: 0x0B3B2A))
        case .milestoneBadgeAnniversaryText: (RGBColor(hex: 0x047857), RGBColor(hex: 0x6EE7B7))
        case .milestoneBadgeWelcome: (RGBColor(hex: 0xEDE9FE), RGBColor(hex: 0x2C2340))
        case .milestoneBadgeWelcomeText: (RGBColor(hex: 0x6D28D9), RGBColor(hex: 0xC4B5FD))
        }
    }
}
