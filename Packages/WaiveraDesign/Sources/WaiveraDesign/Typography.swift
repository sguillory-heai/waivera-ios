#if canImport(UIKit)
    import SwiftUI

    /// Text styles. Every style is a Dynamic Type text style so text scales through the
    /// accessibility sizes; weights are real system weights only (11-pitfalls #47).
    public enum WaiveraFont {
        public static let screenTitle = Font.title2.weight(.heavy)
        public static let sectionTitle = Font.headline
        public static let body = Font.body
        public static let bodyEmphasis = Font.body.weight(.semibold)
        public static let subtitle = Font.subheadline.weight(.semibold)
        public static let caption = Font.footnote
        public static let captionEmphasis = Font.footnote.weight(.semibold)
        public static let label = Font.footnote.weight(.bold)
        public static let eyebrow = Font.caption2.weight(.heavy)
        public static let badge = Font.caption2.weight(.bold)
        public static let button = Font.body.weight(.bold)
    }
#endif
