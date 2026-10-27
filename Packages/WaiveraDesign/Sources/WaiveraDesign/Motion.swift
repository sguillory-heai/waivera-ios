import SwiftUI

/// Shared springs. Movement explains a state change and never delays the user.
public enum Motion {
    /// Things that move or resize on screen.
    public static let spatial = Animation.spring(response: 0.4, dampingFraction: 0.85)
    /// Small, quick movements such as a send button or a badge.
    public static let spatialFast = Animation.spring(response: 0.25, dampingFraction: 0.9)
    /// Opacity and colour changes.
    public static let effects = Animation.easeOut(duration: 0.2)

    /// Spatial motion becomes a plain cross-fade when Reduce Motion is on.
    public static func spatialAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? effects : spatial
    }
}

public extension View {
    /// Animates `value` changes with `Motion.spatial`, honouring Reduce Motion.
    func waiveraSpatialAnimation(value: some Equatable) -> some View {
        modifier(SpatialAnimation(value: value))
    }
}

private struct SpatialAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.spatialAnimation(reduceMotion: reduceMotion), value: value)
    }
}
