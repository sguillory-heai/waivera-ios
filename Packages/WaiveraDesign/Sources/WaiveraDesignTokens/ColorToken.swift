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

    /// This colour drawn over an opaque `background` (source-over), as the eye sees it.
    public func composited(over background: RGBColor) -> RGBColor {
        func mix(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
        return RGBColor(
            red: mix(red, background.red),
            green: mix(green, background.green),
            blue: mix(blue, background.blue),
            alpha: 1
        )
    }

    /// Linear interpolation towards `other`, `fraction` 0...1 (the skeleton pulse).
    public func interpolated(to other: RGBColor, fraction: Double) -> RGBColor {
        let amount = min(1, max(0, fraction))
        func lerp(_ from: Double, _ to: Double) -> Double { from + (to - from) * amount }
        return RGBColor(
            red: lerp(red, other.red),
            green: lerp(green, other.green),
            blue: lerp(blue, other.blue),
            alpha: lerp(alpha, other.alpha)
        )
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

/// Raw brand values. Views read `ColorToken` roles, never these. They are the values the
/// owner approved on Android (`core/designsystem/.../theme/WaiveraPalette.kt` at `brand-rollout`
/// 554e7d1): warm lilac neutrals in light, one plum family that steps by lightness in dark.
/// `AGENTS.md`'s older `#7E57C2` / `#A78BFA` are superseded by these.
public enum BrandPalette {
    public static let white: UInt32 = 0xFFFFFF
    public static let black: UInt32 = 0x000000

    /// The brand gradient, from the logo's looped "W" (top to bottom).
    public static let brandViolet: UInt32 = 0xA640DA
    public static let brandPink: UInt32 = 0xFF6FBC
    public static let brandGold: UInt32 = 0xFFD45C
    /// The dark wash's warm end: gold over plum composited to khaki, peach stays in the family.
    public static let brandPeach: UInt32 = 0xFFB38A
    /// The small pink sparkle beside the all-caught-up ring.
    public static let sparklePink: UInt32 = 0xFF8CC8

    /// The brand violet in light: links, accents and every solid filled control (white on it 6.8:1).
    public static let violet: UInt32 = 0x6A3DC4
    /// Pastel lilac for links, icons and data marks on dark surfaces.
    public static let violetDarkAccent: UInt32 = 0xB79CFF
    /// Text links in dark.
    public static let violetDarkLink: UInt32 = 0xC3ABFF
    /// Filled accent controls in dark, with white text (5.3:1).
    public static let violetDarkFill: UInt32 = 0x8048E6
    /// Violet ink on the lilac tonal fills in light.
    public static let tonalInkLight: UInt32 = 0x4A2391

    /// The "Your day" track's solid event blocks.
    public static let timelineTeal: UInt32 = 0x1FA08B
    public static let timelineViolet: UInt32 = 0x7A55DA
    public static let timelineGold: UInt32 = 0xE0A032

    public static let buttonSheenAlphaLight = 0.10
    public static let buttonSheenAlphaDark = 0.07
    /// Where the sheen has faded out, as a share of the button's height.
    public static let buttonSheenEnd = 0.52
    public static let buttonEdgeAlpha = 0.25
    public static let buttonGlowAlpha = 0.55
    public static let buttonRaiseAlpha = 0.14
    public static let buttonRaiseShadow: UInt32 = 0x140828

    public static let scrimAlpha = 0.36
    /// The long-press focus overlay's scrim (wave 30 O3): the chat behind stops reading.
    public static let focusScrimAlphaLight = 0.70
    public static let focusScrimAlphaDark = 0.76
    public static let washAlpha = 0.08
    public static let borderAlpha = 0.16
    public static let borderStrongAlpha = 0.21
    public static let brandWashAlphaLight = 0.14
    public static let brandWashAlphaDark = 0.18
    public static let brandWashEndAlphaDark = 0.12
}

/// Every colour role in the app. Feature code reads these through `WaiveraDesign`; no literal
/// colours. Each role mirrors Android's `WaiveraColors` of the same name; the first block keeps
/// the names iOS feature code already uses.
public enum ColorToken: String, CaseIterable, Sendable {
    case background
    case surface
    case surfaceMuted
    case border
    case text
    case textSecondary
    case accent
    case accentSoft
    /// Pressed or selected wash.
    case accentWash
    case accentBorder
    case accentBorderStrong
    /// Ink on `accentFill`, `unread`, `selectedFill` and the danger fill: white in both themes.
    case onAccent
    /// Ink on `dangerFill`. Kept for existing call sites; equal to `onDangerFill`.
    case onDanger
    /// Icons, dots and fills that mean "failed". Text uses `dangerText`.
    case danger
    case success
    case warning
    /// Attention (v5 decision 6): unread dots and counts, Needs you, in solid rose.
    case unread
    /// Sheet and dialog scrim.
    case scrim
    /// Switch thumb and other always-white details.
    case thumb
    /// The milestone dot.
    case milestone
    /// The holiday glyph.
    case holiday
    case milestoneBadgeBirthday
    case milestoneBadgeBirthdayText
    case milestoneBadgeAnniversary
    case milestoneBadgeAnniversaryText
    case milestoneBadgeWelcome
    case milestoneBadgeWelcomeText

    /// Sheets and cards above the surface (the dark elevation step; white in light).
    case raised
    /// A text field's fill at rest.
    case field
    /// A text field's edge at rest: 3:1 against the sheet and the field fill.
    case fieldBorder
    case borderStrong
    /// Non-essential text that recedes (3:1); never for anything that must be read.
    case textTertiary
    /// Text links: the accent in light, a lighter lilac in dark.
    case link
    /// Fill of primary buttons and other solid accent controls; white ink sits on it.
    case accentFill
    /// My own message bubble (v5 decision 3, option B).
    case myBubble
    /// The filled buttons' sheen, top edge, glow and the raised secondary's shadow (v5 decision 2).
    case buttonSheen
    case buttonEdge
    case buttonGlow
    case buttonRaise
    /// Ink on `accentSoft` tonal fills.
    case onAccentSoft
    case inverseAccent
    /// An informational total's neutral chip, with `textSecondary` on it.
    case chipNeutral
    case dangerText
    case dangerFill
    case onDangerFill
    case dangerContainer
    case onDangerContainer
    case successText
    case warningText
    case warningContainer
    case onWarningContainer
    /// A person with more than one milestone on the same day.
    case multipleContainer
    case onMultipleContainer
    /// Behind the long-press focus overlay: stronger than `scrim`.
    case focusScrim
    /// Resting skeleton bone, and the static frame under Reduce Motion.
    case skeletonBase
    /// The other end of the skeleton pulse.
    case skeletonHighlight
    /// Fill behind an avatar's initials or fallback glyph (avatars have no border).
    case avatarFill
    /// A tonal button drawn on the brand wash ("Send wishes").
    case tonalOnWash
    case navBar
    case navBarBorder
    /// The selected state of a tab pill, segment or filter chip: solid violet, white ink.
    case selectedFill
    case onSelectedFill
    /// The calendar's selected day: a soft lilac square with bold violet ink.
    case dayTint
    case onDayTint
    /// The dash under today's number.
    case todayMark
    case navBadge
    case snackbar
    case onSnackbar
    case snackbarAction
    /// The brand wash's last stop, alpha included.
    case brandWashEnd
    /// Links, mentions and quote bars inside my own bubble.
    case myBubbleLink
    /// Danger text inside my own bubble.
    case myBubbleDangerText

    public var light: RGBColor { values.light }
    public var dark: RGBColor { values.dark }

    public func value(isDark: Bool) -> RGBColor {
        isDark ? dark : light
    }

    private var values: (light: RGBColor, dark: RGBColor) {
        if let legacy = legacyValues { return legacy }
        if let extended = extendedValues { return extended }
        return brandValues
    }

    // Each case is one table row; splitting further would hide the palette.
    // swiftlint:disable:next cyclomatic_complexity
    private var legacyValues: (light: RGBColor, dark: RGBColor)? {
        switch self {
        case .background: pair(0xF5F2F9, 0x120F17)
        case .surface: pair(0xFFFFFF, 0x1C1824)
        case .surfaceMuted: pair(0xEEE9F4, 0x262032)
        case .border: pair(0xE8E3EE, 0x302A3A)
        case .text: pair(0x1A1324, 0xF4F0FA)
        case .textSecondary: pair(0x5B5169, 0xB3A9C4)
        case .accent: pair(BrandPalette.violet, BrandPalette.violetDarkAccent)
        case .accentSoft, .multipleContainer: pair(0xEEE7FB, 0x2E2448)
        case .accentWash: accentAlpha(BrandPalette.washAlpha)
        case .accentBorder: accentAlpha(BrandPalette.borderAlpha)
        case .accentBorderStrong: accentAlpha(BrandPalette.borderStrongAlpha)
        case .onAccent, .onDanger, .onDangerFill, .onSelectedFill, .onSnackbar, .thumb:
            pair(BrandPalette.white, BrandPalette.white)
        case .danger: pair(0xEF4444, 0xF87171)
        case .success: pair(0x16A34A, 0x4ADE80)
        case .warning: pair(0xD97706, 0xFBBF24)
        case .unread, .navBadge: pair(0xC2255C, 0xD6336C)
        case .scrim:
            (RGBColor(hex: 0, alpha: BrandPalette.scrimAlpha), RGBColor(hex: 0, alpha: BrandPalette.scrimAlpha))
        case .milestone: pair(0xF59E0B, 0xF59E0B)
        case .holiday: pair(0x8B5CF6, 0x8B5CF6)
        case .milestoneBadgeBirthday: pair(0xFEF3C7, 0x3D2A2A)
        case .milestoneBadgeBirthdayText: pair(0x92400E, 0xFDE68A)
        case .milestoneBadgeAnniversary: pair(0xD1FAE5, 0x0F3530)
        case .milestoneBadgeAnniversaryText: pair(0x047857, 0x6EE7B7)
        case .milestoneBadgeWelcome: pair(0xEDE9FE, 0x2F2643)
        case .milestoneBadgeWelcomeText: pair(0x6D28D9, 0xC4B5FD)
        default: nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private var extendedValues: (light: RGBColor, dark: RGBColor)? {
        switch self {
        case .raised: pair(0xFFFFFF, 0x262032)
        case .field: pair(0xF7F4FB, 0x1C1824)
        case .fieldBorder: pair(0x8A7EA4, 0x776B8F)
        case .borderStrong: pair(0x867E93, 0x857A97)
        case .textTertiary: pair(0x8A8197, 0x776D85)
        case .link: pair(BrandPalette.violet, BrandPalette.violetDarkLink)
        case .accentFill, .selectedFill: pair(BrandPalette.violet, BrandPalette.violetDarkFill)
        case .myBubble: pair(0xE2D5FA, 0x3E3058)
        case .onAccentSoft, .onMultipleContainer: pair(BrandPalette.tonalInkLight, 0xE2D6FF)
        case .inverseAccent: pair(BrandPalette.violetDarkAccent, BrandPalette.violet)
        case .chipNeutral: pair(0xECE7F2, 0x2B2436)
        case .dangerText: pair(0xB91C1C, 0xF87171)
        case .dangerFill: pair(0xC42F47, 0xC7375A)
        case .dangerContainer: pair(0xFEE2E2, 0x3A1A24)
        case .onDangerContainer: pair(0xB91C1C, 0xFF8A9B)
        case .successText: pair(0x14763A, 0x4ADE80)
        case .warningText: pair(0xA04A06, 0xFBBF24)
        case .warningContainer: pair(0xFEF3C7, 0x3A2C17)
        case .onWarningContainer: pair(0x92400E, 0xFDE68A)
        case .focusScrim:
            (
                RGBColor(hex: 0, alpha: BrandPalette.focusScrimAlphaLight),
                RGBColor(hex: 0, alpha: BrandPalette.focusScrimAlphaDark)
            )
        case .skeletonBase: pair(0xD6CEE0, 0x332C3F)
        case .skeletonHighlight: pair(0xE6E0EE, 0x3E3650)
        case .avatarFill: pair(0xD4C5EC, 0x4D3F6A)
        case .tonalOnWash: pair(0xD5C6ED, 0x524270)
        default: nil
        }
    }

    private var brandValues: (light: RGBColor, dark: RGBColor) {
        switch self {
        case .navBar: pair(0xFFFFFF, 0x18141F)
        case .navBarBorder: pair(0xE8E3EE, 0x302A3A)
        case .dayTint: pair(0xD6C6F6, 0x46356E)
        case .onDayTint, .myBubbleLink: pair(BrandPalette.tonalInkLight, BrandPalette.violetDarkLink)
        // The board's #8048E6 dash fell to 2.0:1 on the dark tint; the link lilac keeps 5.3:1.
        case .todayMark: pair(BrandPalette.violet, BrandPalette.violetDarkLink)
        case .snackbar: pair(0x2A1145, 0x33195A)
        case .snackbarAction: pair(BrandPalette.violetDarkLink, BrandPalette.violetDarkLink)
        case .buttonSheen:
            (
                RGBColor(hex: BrandPalette.white, alpha: BrandPalette.buttonSheenAlphaLight),
                RGBColor(hex: BrandPalette.white, alpha: BrandPalette.buttonSheenAlphaDark)
            )
        case .buttonEdge:
            (
                RGBColor(hex: BrandPalette.white, alpha: BrandPalette.buttonEdgeAlpha),
                RGBColor(hex: BrandPalette.white, alpha: BrandPalette.buttonEdgeAlpha)
            )
        case .buttonGlow:
            (
                RGBColor(hex: BrandPalette.violet, alpha: BrandPalette.buttonGlowAlpha),
                RGBColor(hex: BrandPalette.violetDarkFill, alpha: BrandPalette.buttonGlowAlpha)
            )
        case .buttonRaise:
            (
                RGBColor(hex: BrandPalette.buttonRaiseShadow, alpha: BrandPalette.buttonRaiseAlpha),
                RGBColor(hex: BrandPalette.black, alpha: BrandPalette.buttonRaiseAlpha)
            )
        case .brandWashEnd:
            (
                RGBColor(hex: BrandPalette.brandGold, alpha: BrandPalette.brandWashAlphaLight),
                RGBColor(hex: BrandPalette.brandPeach, alpha: BrandPalette.brandWashEndAlphaDark)
            )
        // #B91C1C fell to 4.2:1 under the arrival wash on my light bubble.
        case .myBubbleDangerText: pair(0x991B1B, 0xFF8A9B)
        default: pair(BrandPalette.black, BrandPalette.black)
        }
    }

    private func pair(_ light: UInt32, _ dark: UInt32) -> (light: RGBColor, dark: RGBColor) {
        (RGBColor(hex: light), RGBColor(hex: dark))
    }

    private func accentAlpha(_ alpha: Double) -> (light: RGBColor, dark: RGBColor) {
        (RGBColor(hex: BrandPalette.violet, alpha: alpha), RGBColor(hex: BrandPalette.violetDarkAccent, alpha: alpha))
    }
}

/// The opacity of the brand gradient where it washes a surface (celebration cards, sign-in hero).
public enum BrandWash {
    public static func alpha(isDark: Bool) -> Double {
        isDark ? BrandPalette.brandWashAlphaDark : BrandPalette.brandWashAlphaLight
    }

    /// The gradient's stops from the logo SVG.
    public static let violetStop = 0.245
    public static let pinkStop = 0.567
    public static let goldStop = 1.0

    /// The wash's stops (location, colour with alpha) for a theme, as Android's `WaiveraBrand.wash`.
    public static func stops(isDark: Bool) -> [(location: Double, color: RGBColor)] {
        let alpha = alpha(isDark: isDark)
        return [
            (0, RGBColor(hex: BrandPalette.brandViolet, alpha: alpha)),
            (violetStop, RGBColor(hex: BrandPalette.brandViolet, alpha: alpha)),
            (pinkStop, RGBColor(hex: BrandPalette.brandPink, alpha: alpha)),
            (goldStop, ColorToken.brandWashEnd.value(isDark: isDark)),
        ]
    }

    /// The three brand colours, for confetti and other art that picks one colour per piece.
    public static let confettiColors: [RGBColor] = [
        RGBColor(hex: BrandPalette.brandViolet),
        RGBColor(hex: BrandPalette.brandPink),
        RGBColor(hex: BrandPalette.brandGold),
    ]
}
