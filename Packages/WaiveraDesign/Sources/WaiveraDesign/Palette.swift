import SwiftUI
import UIKit

/// Waivera colour roles. Views use these, never literal colours. Values match the
/// Android `WaiveraPalette` so both apps look like one product.
public enum Palette {
    /// Brand purple `#7E57C2`, lifted to `#A78BFA` in dark mode for contrast.
    public static let accent = dynamic(light: 0x7E57C2, dark: 0xA78BFA)
    public static let accentContainer = dynamic(light: 0xEDE4FB, dark: 0x3B2A5C)
    public static let surface = dynamic(light: 0xFBF9FE, dark: 0x141218)
    public static let onSurface = dynamic(light: 0x1C1B1F, dark: 0xE6E1E9)
    public static let error = dynamic(light: 0xB3261E, dark: 0xF2B8B5)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
