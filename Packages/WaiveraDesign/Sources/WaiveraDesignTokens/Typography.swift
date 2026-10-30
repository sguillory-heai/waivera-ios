import Foundation

/// The Plus Jakarta Sans weights the type scale uses. The app bundles one static instance of the
/// variable font per weight (OFL), cut from the same file Android ships.
public enum FontWeightToken: Int, CaseIterable, Sendable {
    case regular = 400
    case medium = 500
    case semibold = 600
    case bold = 700
    case extraBold = 800

    public var postScriptName: String {
        switch self {
        case .regular: "PlusJakartaSans-Regular"
        case .medium: "PlusJakartaSans-Medium"
        case .semibold: "PlusJakartaSans-SemiBold"
        case .bold: "PlusJakartaSans-Bold"
        case .extraBold: "PlusJakartaSans-ExtraBold"
        }
    }

    /// The bundled font file's name, without its `ttf` extension.
    public var fileName: String { postScriptName }
}

/// The iOS text style a Waivera style scales with. Each Waivera style follows the Dynamic Type
/// curve of the system style whose default size is closest to its own.
public enum TextStyleBase: String, CaseIterable, Sendable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption
    case caption2

    /// The system style's size at the default (Large) setting.
    public var defaultSize: Double {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        }
    }

    /// The closest system style for a size; ties go to the smaller style so text never grows faster.
    public static func closest(to size: Double) -> TextStyleBase {
        let candidates: [TextStyleBase] = [
            .largeTitle, .title, .title2, .title3, .body, .callout, .subheadline, .footnote, .caption, .caption2,
        ]
        var best = TextStyleBase.body
        var bestDistance = Double.infinity
        for candidate in candidates {
            let distance = abs(candidate.defaultSize - size)
            if distance < bestDistance || (distance == bestDistance && candidate.defaultSize < best.defaultSize) {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }
}

/// Every text style, with Android's size, line height, weight and tracking (Material slots plus
/// `WaiveraTextStyles`). Sizes are points at the default Dynamic Type size.
public enum TextStyleToken: String, CaseIterable, Sendable {
    // Material 3 slots.
    case headlineLarge
    case headlineMedium
    case headlineSmall
    case titleLarge
    case titleMedium
    case titleSmall
    case bodyLarge
    case bodyMedium
    case bodySmall
    case labelLarge
    case labelMedium
    case labelSmall
    // Waivera styles with no Material slot.
    case eyebrow
    case badge
    case heroEyebrow
    case heroGreeting
    case heroGreetingCompact
    case heroBarTitle
    case heroTitle
    case heroReward
    case heroBody
    case ringNumeral
    case ringDenominator
    case ringNumeralSmall
    case ringDenominatorSmall
    case statNumeral
    case statLabel
    case kicker
    case sectionAction
    case sectionCount
    case displayTime
    case clockTime
    case timelineTime
    case chip
    case panelTitle
    case fieldLabel
    case fieldValue
    case axisLabel

    public struct Spec: Equatable, Sendable {
        public let size: Double
        public let lineHeight: Double
        public let weight: FontWeightToken
        /// Letter spacing in em (a share of the size); SwiftUI's `tracking` takes `size * trackingEm`.
        public let trackingEm: Double

        public var tracking: Double { size * trackingEm }

        /// The same size, line height and tracking in another face, for a row that shows unread
        /// in a heavier weight (Android passes `fontWeight` next to the style).
        public func weighted(_ weight: FontWeightToken?) -> Spec {
            guard let weight else { return self }
            return Spec(size: size, lineHeight: lineHeight, weight: weight, trackingEm: trackingEm)
        }
        /// Extra space between lines on top of the font's own line height.
        public func lineSpacing(fontLineHeight: Double) -> Double { max(0, lineHeight - fontLineHeight) }
    }

    public var spec: Spec { Self.specs[self] ?? Spec(size: 15, lineHeight: 22, weight: .regular, trackingEm: 0) }

    /// The Dynamic Type curve this style follows.
    public var base: TextStyleBase { TextStyleBase.closest(to: spec.size) }

    // One row per style; a table reads better than a switch here.
    private static let specs: [TextStyleToken: Spec] = [
        .headlineLarge: Spec(size: 30, lineHeight: 34, weight: .extraBold, trackingEm: -0.025),
        .headlineMedium: Spec(size: 26, lineHeight: 32, weight: .extraBold, trackingEm: -0.025),
        .headlineSmall: Spec(size: 21, lineHeight: 28, weight: .extraBold, trackingEm: -0.02),
        .titleLarge: Spec(size: 18, lineHeight: 24, weight: .extraBold, trackingEm: -0.015),
        .titleMedium: Spec(size: 17, lineHeight: 22, weight: .semibold, trackingEm: -0.012),
        .titleSmall: Spec(size: 15, lineHeight: 20, weight: .bold, trackingEm: -0.005),
        .bodyLarge: Spec(size: 16, lineHeight: 24, weight: .regular, trackingEm: 0),
        .bodyMedium: Spec(size: 15, lineHeight: 22, weight: .regular, trackingEm: 0),
        .bodySmall: Spec(size: 13, lineHeight: 18, weight: .regular, trackingEm: 0),
        .labelLarge: Spec(size: 16, lineHeight: 22, weight: .bold, trackingEm: 0.005),
        .labelMedium: Spec(size: 13, lineHeight: 18, weight: .semibold, trackingEm: 0),
        .labelSmall: Spec(size: 11.5, lineHeight: 14, weight: .bold, trackingEm: 0),
        .eyebrow: Spec(size: 10.5, lineHeight: 14, weight: .extraBold, trackingEm: 0.1),
        .badge: Spec(size: 11, lineHeight: 14, weight: .bold, trackingEm: 0),
        .heroEyebrow: Spec(size: 12, lineHeight: 16, weight: .bold, trackingEm: 0.09),
        .heroGreeting: Spec(size: 30, lineHeight: 34, weight: .extraBold, trackingEm: -0.028),
        .heroGreetingCompact: Spec(size: 24, lineHeight: 28, weight: .extraBold, trackingEm: -0.028),
        .heroBarTitle: Spec(size: 17, lineHeight: 22, weight: .extraBold, trackingEm: -0.01),
        .heroTitle: Spec(size: 18, lineHeight: 22, weight: .extraBold, trackingEm: -0.015),
        .heroReward: Spec(size: 26, lineHeight: 32, weight: .extraBold, trackingEm: -0.025),
        .heroBody: Spec(size: 13, lineHeight: 18, weight: .regular, trackingEm: 0),
        .ringNumeral: Spec(size: 26, lineHeight: 28, weight: .extraBold, trackingEm: -0.03),
        .ringDenominator: Spec(size: 15, lineHeight: 18, weight: .bold, trackingEm: 0),
        .ringNumeralSmall: Spec(size: 20, lineHeight: 22, weight: .extraBold, trackingEm: -0.03),
        .ringDenominatorSmall: Spec(size: 12, lineHeight: 14, weight: .bold, trackingEm: 0),
        .statNumeral: Spec(size: 20, lineHeight: 22, weight: .extraBold, trackingEm: -0.02),
        .statLabel: Spec(size: 12, lineHeight: 15, weight: .medium, trackingEm: 0),
        .kicker: Spec(size: 12, lineHeight: 16, weight: .bold, trackingEm: 0.01),
        .sectionAction: Spec(size: 14, lineHeight: 18, weight: .bold, trackingEm: 0),
        .sectionCount: Spec(size: 13, lineHeight: 16, weight: .extraBold, trackingEm: 0),
        .displayTime: Spec(size: 26, lineHeight: 30, weight: .extraBold, trackingEm: -0.03),
        .clockTime: Spec(size: 16, lineHeight: 20, weight: .semibold, trackingEm: -0.01),
        .timelineTime: Spec(size: 13, lineHeight: 18, weight: .bold, trackingEm: -0.005),
        .chip: Spec(size: 12, lineHeight: 16, weight: .bold, trackingEm: 0),
        .panelTitle: Spec(size: 14, lineHeight: 18, weight: .semibold, trackingEm: -0.01),
        .fieldLabel: Spec(size: 13, lineHeight: 17, weight: .medium, trackingEm: 0),
        .fieldValue: Spec(size: 17, lineHeight: 23, weight: .bold, trackingEm: -0.005),
        .axisLabel: Spec(size: 11, lineHeight: 14, weight: .medium, trackingEm: 0),
    ]
}

/// The legacy `WaiveraFont` names feature code already uses, and the style each now resolves to.
public enum LegacyFontRole: String, CaseIterable, Sendable {
    case screenTitle
    case sectionTitle
    case body
    case bodyEmphasis
    case subtitle
    case caption
    case captionEmphasis
    case label
    case eyebrow
    case badge
    case button

    public var style: TextStyleToken {
        switch self {
        case .screenTitle: .headlineSmall
        case .sectionTitle: .titleMedium
        case .body: .bodyMedium
        case .bodyEmphasis: .titleSmall
        case .subtitle: .panelTitle
        case .caption: .bodySmall
        case .captionEmphasis: .labelMedium
        case .label: .kicker
        case .eyebrow: .eyebrow
        case .badge: .badge
        case .button: .labelLarge
        }
    }
}

/// The Dynamic Type sizes, in order, as plain data so the large-text rules are unit tested.
/// Mirrors SwiftUI's `DynamicTypeSize`.
public enum TextSizeCategory: Int, CaseIterable, Comparable, Sendable {
    case xSmall
    case small
    case medium
    case large
    case xLarge
    case xxLarge
    case xxxLarge
    case accessibility1
    case accessibility2
    case accessibility3
    case accessibility4
    case accessibility5

    public static func < (lhs: TextSizeCategory, rhs: TextSizeCategory) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Body text size in points at this category (Apple's published table).
    public var bodySize: Double {
        switch self {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        }
    }

    /// The text scale against the default, Android's `fontScale`.
    public var scale: Double { bodySize / TextSizeCategory.large.bodySize }
}

/// Android's font-scale thresholds, expressed as Dynamic Type sizes.
public enum TypeScale {
    /// Above this scale layouts take their large-text form (Android `LARGE_FONT_SCALE`, 130%).
    public static let largeScale = 1.3
    /// From this scale layouts take their largest-text form (Android `EXTRA_LARGE_FONT_SCALE`, 150%).
    public static let extraLargeScale = 1.5
    /// The ring's count stops growing at 130%.
    public static let ringMaxScale = 1.3

    /// True above 130%: xxxLarge and every accessibility size.
    public static func isLarge(_ category: TextSizeCategory) -> Bool { category.scale > largeScale }

    /// True from 150%: the accessibility sizes.
    public static func isExtraLarge(_ category: TextSizeCategory) -> Bool { category.scale >= extraLargeScale }

    /// The largest category whose scale is at most `scale`: the cap for a view that stops growing.
    public static func cap(atScale scale: Double) -> TextSizeCategory {
        TextSizeCategory.allCases.last { $0.scale <= scale } ?? .large
    }
}
