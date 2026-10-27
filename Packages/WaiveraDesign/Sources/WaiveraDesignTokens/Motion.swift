/// Motion tokens from the UX research table. Define once, never hand-pick curves in features.
public enum MotionToken: String, CaseIterable, Sendable {
    /// Button and row press: snappy 0.2s, scale 0.96.
    case press
    /// Colour, opacity, badge, toggle: smooth 0.25s.
    case state
    /// Expand/collapse, list insert/remove, reorder: smooth 0.35s.
    case layout
    /// Screen changes: the system push / zoom transition.
    case navigate
    /// Rare earned moments (task done, all caught up): bouncy 0.4s, extra bounce 0.1.
    case celebrate
}

/// What an animation should be, as data. `WaiveraDesign` turns this into a SwiftUI `Animation`.
public enum MotionCurve: Equatable, Sendable {
    case snappy(duration: Double)
    case smooth(duration: Double)
    case bouncy(duration: Double, extraBounce: Double)
    /// Leave the transition to the system navigation stack.
    case system
    /// The `reduced` token: a short cross-fade.
    case crossFade(duration: Double)
    /// No animation at all.
    case none
}

public enum MotionPolicy {
    public static let pressScale = 0.96
    public static let reducedCrossFadeDuration = 0.15
    /// Message arrival highlight, tuned by hand in the Expo build (11-pitfalls #38).
    public static let arrivalHighlightDuration = 0.84
    /// How long a deep-linked message stays highlighted (00-inventory §8).
    public static let targetHighlightDuration = 3.2
    /// Skeleton pulse half-period (opacity 0.45 ↔ 0.85 over 650ms).
    public static let skeletonPulseDuration = 0.65
    public static let skeletonOpacityRange = (low: 0.45, high: 0.85)

    /// The curve for a token, swapping to the `reduced` token when Reduce Motion is on.
    public static func curve(for token: MotionToken, reduceMotion: Bool) -> MotionCurve {
        if reduceMotion {
            switch token {
            // Presses are frequent; under Reduce Motion they get no animation at all.
            case .press: return .none
            case .navigate: return .system
            case .state, .layout, .celebrate: return .crossFade(duration: reducedCrossFadeDuration)
            }
        }
        switch token {
        case .press: return .snappy(duration: 0.2)
        case .state: return .smooth(duration: 0.25)
        case .layout: return .smooth(duration: 0.35)
        case .navigate: return .system
        case .celebrate: return .bouncy(duration: 0.4, extraBounce: 0.1)
        }
    }

    /// Scale applied while a control is pressed.
    public static func pressedScale(reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : pressScale
    }

    /// Skeletons shimmer only when motion is allowed; otherwise they hold a static mid tone.
    public static func skeletonAnimates(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
