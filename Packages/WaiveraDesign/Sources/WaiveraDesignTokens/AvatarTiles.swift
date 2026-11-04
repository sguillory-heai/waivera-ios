/// The fallback avatar for someone without a photo (Android `AvatarTiles`, tile B): white
/// initials on one of six on-brand gradients picked from the name, so a person keeps the same
/// colours on every screen and on both platforms, with a soft sheen across the top and a faint
/// inner edge. Notifications keep the app icon on iOS (WAIV-2939), so only the app draws these.
public enum AvatarTiles {
    /// Gradient start (top leading) and end (bottom trailing) of each tile colour.
    public static let pairs: [(start: RGBColor, end: RGBColor)] = [
        (RGBColor(hex: 0x7E57C2), RGBColor(hex: 0xA640DA)),
        (RGBColor(hex: 0xB4407E), RGBColor(hex: 0xFF6FBC)),
        (RGBColor(hex: 0x1F8F7E), RGBColor(hex: 0x3CC2A6)),
        (RGBColor(hex: 0x4F5BD5), RGBColor(hex: 0x8A6CF0)),
        (RGBColor(hex: 0xC2643A), RGBColor(hex: 0xF0A04B)),
        (RGBColor(hex: 0x6A3FA0), RGBColor(hex: 0xC04FD0)),
    ]

    /// White over the top of the tile.
    public static let sheenOpacity = 0.16
    /// The sheen's centre above the tile and its radius, as shares of the side.
    public static let sheenCenter = 0.15
    public static let sheenRadius = 0.95
    /// The inner edge, white, and its width as a share of the side.
    public static let edgeOpacity = 0.24
    public static let edgeFraction = 0.016
    /// The initials' soft deep-plum shadow, with its blur and drop as shares of the side.
    public static let shadow = RGBColor(hex: 0x280A3C, alpha: Double(0x5A) / 255)
    public static let shadowBlur = 0.03
    public static let shadowDrop = 0.012

    /// The same name always lands on the same colours; case and outer spaces don't matter. The
    /// hash is Android's (31 × hash + UTF-16 unit, wrapping 32-bit), so both apps agree.
    public static func index(for name: String) -> Int {
        let key = name.trimmingWhitespace().lowercased()
        var hash: Int32 = 0
        for unit in key.utf16 { hash = hash &* 31 &+ Int32(unit) }
        let count = Int32(pairs.count)
        return Int(((hash % count) + count) % count)
    }

    public static func pair(for name: String) -> (start: RGBColor, end: RGBColor) { pairs[index(for: name)] }
}

extension String {
    /// Kotlin `trim()`: spaces and controls at both ends, without Foundation.
    fileprivate func trimmingWhitespace() -> String {
        let isTrimmed: (Character) -> Bool = { $0.isWhitespace || $0.unicodeScalars.allSatisfy { $0.value < 0x20 } }
        guard let first = firstIndex(where: { !isTrimmed($0) }), let last = lastIndex(where: { !isTrimmed($0) }) else {
            return ""
        }
        return String(self[first...last])
    }
}
