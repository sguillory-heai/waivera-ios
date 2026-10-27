import CoreGraphics

/// Spacing scale in steps of 4pt. Layouts use these instead of literal numbers.
public enum Spacing {
    public static let extraSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let extraLarge: CGFloat = 32

    /// Apple's minimum hit target.
    public static let minHitTarget: CGFloat = 44
}
