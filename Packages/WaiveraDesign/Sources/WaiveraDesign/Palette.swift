#if canImport(UIKit)
    import SwiftUI
    import UIKit

    public extension Color {
        /// A colour token that resolves for the current light or dark appearance.
        init(token: ColorToken) {
            self.init(
                uiColor: UIColor { traits in
                    UIColor(rgb: token.value(isDark: traits.userInterfaceStyle == .dark))
                }
            )
        }
    }

    /// Colour roles for views. Feature code uses these, never literal colours.
    public enum Palette {
        public static let background = Color(token: .background)
        public static let surface = Color(token: .surface)
        public static let surfaceMuted = Color(token: .surfaceMuted)
        public static let border = Color(token: .border)
        public static let text = Color(token: .text)
        public static let textSecondary = Color(token: .textSecondary)
        public static let accent = Color(token: .accent)
        public static let accentSoft = Color(token: .accentSoft)
        public static let accentWash = Color(token: .accentWash)
        public static let accentBorder = Color(token: .accentBorder)
        public static let accentBorderStrong = Color(token: .accentBorderStrong)
        public static let onAccent = Color(token: .onAccent)
        public static let onDanger = Color(token: .onDanger)
        public static let danger = Color(token: .danger)
        public static let success = Color(token: .success)
        public static let warning = Color(token: .warning)
        public static let unread = Color(token: .unread)
        public static let scrim = Color(token: .scrim)
        public static let thumb = Color(token: .thumb)
        public static let milestone = Color(token: .milestone)
        public static let holiday = Color(token: .holiday)
    }

    extension UIColor {
        convenience init(rgb: RGBColor) {
            self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
        }
    }
#endif
