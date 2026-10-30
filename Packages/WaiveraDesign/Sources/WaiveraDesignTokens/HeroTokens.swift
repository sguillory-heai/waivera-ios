import Foundation

/// The full-bleed plum hero's colours (Android `WaiveraHeroColors`). Light and dark differ only in
/// the header gradient, the glass card's fill and the sign-in sheet.
public enum HeroColorToken: String, CaseIterable, Sendable {
    case headerTop
    case headerBottom
    /// The pink glow in the top-end corner.
    case glowPink
    /// The violet glow in the bottom-start corner.
    case glowViolet
    /// Headings, numbers, the logo's ink and the bar title on the hero.
    case onHeader
    /// Supporting lines, eyebrows and labels on the hero.
    case onHeaderSecondary
    /// The glass summary card and its hairline.
    case card
    case cardBorder
    /// A stat tile on the hero and its hairline.
    case tile
    case tileBorder
    /// The rings' unfilled track.
    case ringTrack
    /// The progress and reward rings' solid arc (v5 rule A: never a gradient).
    case ringArc
    /// The account avatar's glass fill on the hero bar.
    case accountFill
    /// The countdown chip ("in 30 min"): mint on a deep teal glass.
    case chip
    case onChip
    /// The clock glyph beside the next item.
    case nextIcon
    /// The sign-in sheet: white in light, the plum page in dark.
    case sheet

    public func value(isDark: Bool) -> RGBColor {
        isDark ? values.dark : values.light
    }

    // One table row per case, as in `ColorToken`.
    private var values: (light: RGBColor, dark: RGBColor) {
        switch self {
        case .headerTop: (RGBColor(hex: 0x2A1145), RGBColor(hex: 0x1B0F29))
        case .headerBottom: (RGBColor(hex: 0x4C2384), RGBColor(hex: 0x33195A))
        case .glowPink: Self.both(RGBColor(hex: BrandPalette.brandPink, alpha: 0.42))
        case .glowViolet: Self.both(RGBColor(hex: BrandPalette.brandViolet, alpha: 0.55))
        case .onHeader: Self.both(RGBColor(hex: BrandPalette.white))
        // The concept's 62-72% white; 80% keeps 4.5:1 under the glows at full strength.
        case .onHeaderSecondary: Self.both(RGBColor(hex: BrandPalette.white, alpha: 0.8))
        case .card: (RGBColor(hex: BrandPalette.white, alpha: 0.08), RGBColor(hex: BrandPalette.white, alpha: 0.06))
        case .cardBorder: Self.both(RGBColor(hex: BrandPalette.white, alpha: 0.13))
        case .tile: Self.both(RGBColor(hex: BrandPalette.white, alpha: 0.07))
        case .tileBorder: Self.both(RGBColor(hex: BrandPalette.white, alpha: 0.1))
        case .ringTrack: Self.both(RGBColor(hex: BrandPalette.white, alpha: 0.14))
        case .ringArc: Self.both(RGBColor(hex: 0xE1D3FF))
        case .accountFill: Self.both(RGBColor(hex: BrandPalette.white, alpha: 0.16))
        case .chip: Self.both(RGBColor(hex: 0x0A6B60, alpha: Double(0x66) / 255))
        case .onChip: Self.both(RGBColor(hex: 0x8EF0DC))
        case .nextIcon: Self.both(RGBColor(hex: 0xFFB8DC))
        case .sheet: (RGBColor(hex: 0xFFFFFF), RGBColor(hex: 0x120F17))
        }
    }

    private static func both(_ color: RGBColor) -> (light: RGBColor, dark: RGBColor) {
        (color, color)
    }
}

/// Hero measurements in points (Android `WaiveraHero`).
public enum HeroMetrics {
    /// The header gradient's CSS angle: top, leaning start, to bottom, leaning end.
    public static let headerAngleDegrees = 165.0
    /// The concept's frame width; trails and glows are placed on it and scaled to the window.
    public static let frameWidth = 390.0
    /// Glows fade out at this share of their radius.
    public static let glowFade = 0.65
    public static let pinkRadius = 180.0
    public static let pinkEndInset = 40.0
    public static let pinkTop = 30.0
    public static let violetRadius = 190.0
    public static let violetStart = 20.0
    public static let violetBelow = 30.0

    public static let sheetCornerSignIn = 32.0
    public static let tabSheetCorner = 28.0
    public static let sheetOverlap = 44.0
    /// The tab sheet's first band: its curve and the padding above its first section.
    public static let tabSheetLip = 22.0
    public static let tabSheetLipShort = 16.0
    public static let barSheetLipCompact = 12.0
    public static let profileAvatar = 88.0
    public static let profileAvatarCompact = 64.0
    public static let headerHeight = 260.0
    public static let headerHeightMax = 340.0
    public static let headerWindowShare = 0.36
    public static let headerHeightCompact = 116.0
    public static let gateHeaderHeight = 120.0
    public static let lockupCenterShare = 0.42
    public static let lockup = 42.0
    public static let lockupCompact = 32.0
    public static let entranceRise = 24.0
    public static let barHeight = 56.0
    public static let barMark = 30.0
    public static let barAvatar = 38.0
    /// Windows shorter than this compact the hero so the sheet's first rows show.
    public static let shortWindowHeight = 700.0

    public static func isShortWindow(height: Double) -> Bool {
        height > 0 && height < shortWindowHeight
    }

    /// The tab sheet's lip for a window height.
    public static func tabSheetLip(windowHeight: Double) -> Double {
        isShortWindow(height: windowHeight) ? tabSheetLipShort : tabSheetLip
    }

    /// The sign-in header's height: the share of a tall window, between the regular and max height.
    public static func signInHeaderHeight(windowHeight: Double, compact: Bool) -> Double {
        if compact { return headerHeightCompact }
        return min(headerHeightMax, max(headerHeight, windowHeight * headerWindowShare))
    }

    /// Start and end points of a CSS `linear-gradient(<degrees>deg)` over a box, in unit space
    /// (0...1 on each axis), so SwiftUI's `LinearGradient(startPoint:endPoint:)` draws the same line.
    public static func cssGradientPoints(
        width: Double,
        height: Double,
        degrees: Double = headerAngleDegrees
    ) -> (start: (x: Double, y: Double), end: (x: Double, y: Double)) {
        guard width > 0, height > 0 else { return ((0.5, 0), (0.5, 1)) }
        let radians = degrees * .pi / 180
        let directionX = sin(radians)
        let directionY = -cos(radians)
        let half = (abs(width * directionX) + abs(height * directionY)) / 2
        let centerX = width / 2
        let centerY = height / 2
        let start = ((centerX - directionX * half) / width, (centerY - directionY * half) / height)
        let end = ((centerX + directionX * half) / width, (centerY + directionY * half) / height)
        return (start, end)
    }
}

/// Which light trail a hero draws, traced from the logo's looped "W".
public enum HeroTrail: Sendable {
    case signIn
    case tab
    case reward
    case none

    /// Where the trail's 35 x 26 viewport is fitted, on the 390-wide frame.
    public struct Placement: Equatable, Sendable {
        public let left: Double
        public let top: Double
        public let width: Double
        public let height: Double
        /// Stroke width in viewport units.
        public let stroke: Double
        public let alpha: Double
        /// Whether the thin second strand runs beside the main one.
        public let strand: Bool
    }

    public var placement: Placement? {
        switch self {
        case .signIn:
            Placement(left: -20, top: -150, width: 680, height: 505, stroke: 0.42, alpha: 0.55, strand: true)
        case .tab:
            Placement(left: 120, top: 40, width: 420, height: 320, stroke: 1.3, alpha: 0.16, strand: false)
        case .reward:
            Placement(left: -40, top: -170, width: 680, height: 505, stroke: 1.2, alpha: 0.16, strand: false)
        case .none:
            nil
        }
    }

    public static let viewWidth = 35.0
    public static let viewHeight = 26.0
    /// The trail's horizontal gradient runs from x -2 to 38 in viewport units, pink at 55%.
    public static let gradientStartX = -2.0
    public static let gradientEndX = 38.0
    public static let gradientPinkStop = 0.55
    public static let strandStroke = 0.18
    public static let strandAlpha = 0.6

    /// The main trail and the strand, as SVG path data (`concepts/src/A.html`).
    public static let mainPath =
        "M-2 9.2C-2 9.2 3.9 23.7 10.25 23.47C14.58 23.24 22.76 10.47 21.56 5.5C20.36 .54 15.3 .54 "
        + "14.34 5.5C13.38 10.47 22.28 23.71 25.17 23.47C28.05 23.24 33.5 16.9 38 9.2"
    public static let strandPath = "M-2 10.4C-2 10.4 4.2 24.6 10.4 24.3C15 24 23.4 10.9 22.3 5.4"
}
