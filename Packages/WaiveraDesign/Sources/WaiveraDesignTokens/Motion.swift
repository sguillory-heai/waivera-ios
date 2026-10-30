import Foundation

/// The motion vocabulary. Define once, never hand-pick curves in features. Each token mirrors
/// Android's `MotionToken` and `WaiveraMotionScheme` (`brand-rollout` 554e7d1).
public enum MotionToken: String, CaseIterable, Sendable {
    /// Button and row press: a quick spatial spring to the control's `PressDepth`.
    case press
    /// Colour, opacity, badge and toggle changes. Never overshoots.
    case state
    /// Expand/collapse, list insert/remove, reorder.
    case layout
    /// Screen changes. iOS leaves pushes and the back swipe to the system navigation stack.
    case navigate
    /// Rare, earned moments only: all caught up, a celebration.
    case celebrate
}

/// A damped spring as Android's Compose `spring(dampingRatio, stiffness)` with unit mass.
public struct SpringSpec: Equatable, Sendable {
    public let stiffness: Double
    public let dampingRatio: Double

    public init(stiffness: Double, dampingRatio: Double) {
        self.stiffness = stiffness
        self.dampingRatio = dampingRatio
    }

    /// SwiftUI's `spring(response:dampingFraction:)` response: the undamped period, 2π/√k.
    public var response: Double { 2 * .pi / stiffness.squareRoot() }
    /// SwiftUI's `dampingFraction` is the damping ratio.
    public var dampingFraction: Double { dampingRatio }
    /// The damping coefficient for `interpolatingSpring(mass: 1, stiffness:damping:)`: 2ζ√k.
    public var damping: Double { 2 * dampingRatio * stiffness.squareRoot() }

    /// How far past its target the spring travels, as a share of the distance (0 when ζ ≥ 1).
    public var overshoot: Double {
        guard dampingRatio < 1 else { return 0 }
        return exp(-dampingRatio * .pi / (1 - dampingRatio * dampingRatio).squareRoot())
    }

    /// Time until the motion stays within `threshold` of its distance (envelope estimate).
    public func settlingTime(threshold: Double = 0.01) -> Double {
        let omega = stiffness.squareRoot()
        let decay = max(dampingRatio, 0.05) * omega
        return -log(threshold) / decay
    }
}

/// A cubic Bézier easing, as CSS `cubic-bezier` and SwiftUI `timingCurve` take it.
public struct Easing: Equatable, Sendable {
    public let controlX1: Double
    public let controlY1: Double
    public let controlX2: Double
    public let controlY2: Double

    /// Material's standard curve, Compose `FastOutSlowInEasing`.
    public static let fastOutSlowIn = Easing(controlX1: 0.4, controlY1: 0, controlX2: 0.2, controlY2: 1)
    /// Compose `LinearOutSlowInEasing`: starts at full speed, slows into place.
    public static let linearOutSlowIn = Easing(controlX1: 0, controlY1: 0, controlX2: 0.2, controlY2: 1)
    public static let linear = Easing(controlX1: 0, controlY1: 0, controlX2: 1, controlY2: 1)

    /// The eased value at time `progress` (0...1), solved on the curve's x by bisection.
    public func value(at progress: Double) -> Double {
        let time = min(1, max(0, progress))
        if self == .linear { return time }
        var low = 0.0
        var high = 1.0
        var parameter = time
        for _ in 0..<40 {
            parameter = (low + high) / 2
            if Self.bezier(parameter, controlX1, controlX2) < time { low = parameter } else { high = parameter }
        }
        return Self.bezier(parameter, controlY1, controlY2)
    }

    private static func bezier(_ param: Double, _ first: Double, _ second: Double) -> Double {
        let inverse = 1 - param
        return 3 * inverse * inverse * param * first + 3 * inverse * param * param * second + param * param * param
    }
}

/// A timed animation: duration, delay (both seconds) and easing.
public struct TweenSpec: Equatable, Sendable {
    public let duration: Double
    public let delay: Double
    public let easing: Easing

    public init(duration: Double, delay: Double = 0, easing: Easing = .fastOutSlowIn) {
        self.duration = duration
        self.delay = delay
        self.easing = easing
    }
}

/// What an animation should be, as data. `WaiveraDesign` turns it into a SwiftUI `Animation`.
public enum MotionCurve: Equatable, Sendable {
    case spring(SpringSpec)
    case tween(TweenSpec)
    /// Jump to the end at once (Compose `snap()`): no animation.
    case none
    /// Leave the transition to the system navigation stack.
    case system
}

/// How far a control sinks under the finger, by its size (Android M1-04). `scale` is the press and
/// `longPressScale` how far a control with a long press keeps sinking while the hold arms.
public enum PressDepth: String, CaseIterable, Sendable {
    /// Full-bleed list rows: settings, switch and conversation rows.
    case row
    /// Cards with a margin: agenda, bookmark and celebration cards.
    case card
    /// Buttons, chips, segments and message bubbles.
    case button
    /// Small targets: icon buttons, the tab icon, the send glyph, a search clear.
    case compact

    public var scale: Double {
        switch self {
        case .row: 0.985
        case .card: 0.97
        case .button: 0.96
        case .compact: 0.90
        }
    }

    public var longPressScale: Double {
        switch self {
        case .row: 0.97
        case .card: 0.95
        case .button: 0.93
        case .compact: 0.86
        }
    }

    /// Rows and cards also take a light tint on touch-down (M3-08); buttons dip far enough alone.
    public var tintsOnTouch: Bool { self == .row || self == .card }
}

/// Every named motion spec, with Android's exact values.
public enum MotionSpec {
    public static let fastSpatial = SpringSpec(stiffness: 1400, dampingRatio: 0.9)
    public static let defaultSpatial = SpringSpec(stiffness: 700, dampingRatio: 0.9)
    public static let fastEffects = SpringSpec(stiffness: 3800, dampingRatio: 1)
    public static let celebrate = SpringSpec(stiffness: 200, dampingRatio: 0.8)
    /// The way back out of a press after the finger lifts: springs to about 1.004 and settles.
    public static let pressRelease = SpringSpec(stiffness: 800, dampingRatio: 0.6)
    /// The way out of a press a scroll took: no hold, no overshoot.
    public static let pressCancel = SpringSpec(stiffness: 2400, dampingRatio: 1)
    /// Your own message landing: a quick, slightly springy pop up from the composer.
    public static let sendPop = SpringSpec(stiffness: 520, dampingRatio: 0.62)
    /// A control that changed state on its own spot: a tab icon, a count, a check.
    public static let pop = SpringSpec(stiffness: 900, dampingRatio: 0.5)

    /// The leaving side of a swap: gone before the arriving side is halfway.
    public static let exit = TweenSpec(duration: 0.060, easing: .linearOutSlowIn)
    /// The arriving side of a swap: its fade waits 40 ms, then eases in over 150 ms.
    public static let swapEnter = TweenSpec(duration: 0.150, delay: 0.040, easing: .linearOutSlowIn)
    /// Content that waits for leaving content to clear first (an empty state after the last card).
    public static let enterAfterExit = TweenSpec(duration: 0.120, delay: 0.040, easing: .fastOutSlowIn)
    /// The reduced-motion cross-fade.
    public static let reducedFade = TweenSpec(duration: 0.150, easing: .linear)
    /// One half of the skeleton's breath, eased so it slows at each end (M1-16).
    public static let skeletonPulse = TweenSpec(duration: 0.900, easing: .fastOutSlowIn)
    /// The confetti burst's timeline.
    public static let celebrateBurst = TweenSpec(duration: 1.400, easing: .linear)
}

/// Fixed durations and constants of the motion system (seconds unless noted).
public enum MotionTiming {
    /// Every press is visible at least this long before it releases (unless a scroll took it).
    public static let minVisiblePress = 0.090
    /// A held press waits this long before it sinks toward its long press.
    public static let longPressArmDelay = 0.150
    /// The shortest sink, for a long-press duration barely past the arm delay.
    public static let longPressMinSink = 0.100
    /// iOS's long-press duration for messages and rows (SwiftUI's default `minimumDuration`).
    public static let longPressDuration = 0.5
    /// How long "Synced" shows, its check popped, before the sync line folds away.
    public static let syncedBeat = 0.900
    /// How long a send waits before it says "Sending…".
    public static let sendingLabelDelay = 0.400
    /// How long the send button keeps its enabled fill after a send, so its pop is seen.
    public static let sendPayoffHold = 0.180
    /// How long a removed item shows its control's change before it starts to leave.
    public static let removalBeat = 0.120
    /// How long a removal may still be on screen before it counts as not held.
    public static let removalHeld = 1.000
    /// How long a landing or a toggled time line holds list placement animation off.
    public static let listSettle = 0.250
    /// The longest the focus overlay's close waits for the change it led to.
    public static let focusCloseWait = 0.600
    /// The wrong sign-in shake waits while the error banner opens above the form.
    public static let rejectShakeAfterPush = 0.100
    /// The selected tab pill grows out from the glyph: its starting horizontal scale.
    public static let tabPillStartScaleX = 0.55
    /// Where a pop starts: a little small, so the spring's overshoot reads as a pop.
    public static let popStartScale = 0.8
    /// Where a swap's arriving side starts its pop.
    public static let swapStartScale = 0.92
    /// A horizontal swap slides a third of its width; a vertical one (a count roll) half its height.
    public static let swapSlideDivisor = 3.0
    public static let swapRollDivisor = 2.0
    /// Message arrival highlight.
    public static let arrivalHighlight = 0.84
    /// How long a deep-linked message stays highlighted.
    public static let targetHighlight = 3.2
}

/// A wrong sign-in's shake: fractions of `Spacing.shakeAmplitude` at times (seconds), each segment
/// eased with `fastOutSlowIn`, starting and ending at rest (Android `rejectShake`, M1-15).
public enum ShakeKeyframes {
    public static let duration = 0.300
    public static let frames: [(time: Double, value: Double)] = [
        (0, 0),
        (0.040, -1),
        (0.110, 1),
        (0.180, -0.6),
        (0.245, 0.25),
        (0.300, 0),
    ]

    /// The shake's offset (in amplitudes) at `time` seconds after it starts.
    public static func value(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        for index in 1..<frames.count where time <= frames[index].time {
            let from = frames[index - 1]
            let next = frames[index]
            let progress = (time - from.time) / (next.time - from.time)
            return from.value + (next.value - from.value) * Easing.fastOutSlowIn.value(at: progress)
        }
        return 0
    }
}

/// Which way a directional swap moves.
public enum SwapAxis: Sendable {
    /// A period step: slides across.
    case horizontal
    /// A count roll: slides up and down.
    case vertical
}

public enum MotionPolicy {
    /// Kept for existing call sites.
    public static let pressScale = PressDepth.button.scale
    public static let reducedCrossFadeDuration = MotionSpec.reducedFade.duration
    public static let arrivalHighlightDuration = MotionTiming.arrivalHighlight
    public static let targetHighlightDuration = MotionTiming.targetHighlight
    public static let skeletonPulseDuration = MotionSpec.skeletonPulse.duration

    /// The curve for a token. Under Reduce Motion spatial motion snaps and effects become a short
    /// cross-fade, so nothing moves and nothing blocks input.
    public static func curve(for token: MotionToken, reduceMotion: Bool) -> MotionCurve {
        switch token {
        case .press: return reduceMotion ? .none : .spring(MotionSpec.fastSpatial)
        case .state: return reduceMotion ? .tween(MotionSpec.reducedFade) : .spring(MotionSpec.fastEffects)
        case .layout: return reduceMotion ? .none : .spring(MotionSpec.defaultSpatial)
        case .navigate: return .system
        case .celebrate: return reduceMotion ? .tween(MotionSpec.reducedFade) : .spring(MotionSpec.celebrate)
        }
    }

    /// Scale while a control of `depth` is pressed; 1 under Reduce Motion, where a tint answers instead.
    public static func pressedScale(_ depth: PressDepth = .button, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : depth.scale
    }

    /// Scale a control of `depth` has sunk to when its long press fires.
    public static func longPressScale(_ depth: PressDepth, reduceMotion: Bool) -> Double {
        reduceMotion ? 1 : depth.longPressScale
    }

    /// The touch-down tint's opacity for a press.
    public static func pressedTint(_ depth: PressDepth, reduceMotion: Bool) -> Double {
        if reduceMotion { return Emphasis.pressedTint }
        return depth.tintsOnTouch ? Emphasis.standardPressedTint : 0
    }

    /// How long a release waits so its press was visible for the minimum time.
    public static func releaseDelay(pressedFor: Double, cancelled: Bool = false) -> Double {
        cancelled ? 0 : min(MotionTiming.minVisiblePress, max(0, MotionTiming.minVisiblePress - pressedFor))
    }

    /// How long a held press sinks toward its long press: the rest of the long-press duration.
    public static func longPressSink(longPressDuration: Double = MotionTiming.longPressDuration) -> TweenSpec {
        let sink = max(MotionTiming.longPressMinSink, longPressDuration - MotionTiming.longPressArmDelay)
        return TweenSpec(duration: sink, easing: .linear)
    }

    /// The release after a press: the bouncy release, or the plain cancel when a scroll took it.
    public static func release(cancelled: Bool, reduceMotion: Bool) -> MotionCurve {
        if reduceMotion { return .none }
        return .spring(cancelled ? MotionSpec.pressCancel : MotionSpec.pressRelease)
    }

    public static func pop(reduceMotion: Bool) -> MotionCurve {
        reduceMotion ? .none : .spring(MotionSpec.pop)
    }

    public static func sendPop(reduceMotion: Bool) -> MotionCurve {
        reduceMotion ? .none : .spring(MotionSpec.sendPop)
    }

    /// A swap's leaving side: the quick exit, or gone at once under Reduce Motion.
    public static func swapExit(reduceMotion: Bool) -> MotionCurve {
        reduceMotion ? .none : .tween(MotionSpec.exit)
    }

    /// A swap's arriving side: the delayed fade, or the short fade at once under Reduce Motion.
    public static func swapEnter(reduceMotion: Bool) -> MotionCurve {
        .tween(reduceMotion ? MotionSpec.reducedFade : MotionSpec.swapEnter)
    }

    /// Content leaving so other content can take its place (not a swap side).
    public static func exit(reduceMotion: Bool) -> MotionCurve {
        .tween(reduceMotion ? MotionSpec.reducedFade : MotionSpec.exit)
    }

    public static func enterAfterExit(reduceMotion: Bool) -> MotionCurve {
        .tween(reduceMotion ? MotionSpec.reducedFade : MotionSpec.enterAfterExit)
    }

    /// Whether a swap slides or pops; under Reduce Motion it only fades.
    public static func swapMoves(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// Skeletons breathe only when motion is allowed; otherwise they hold the base colour.
    public static func skeletonAnimates(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// The rejection shake runs only when motion is allowed; the error state alone answers otherwise.
    public static func shakes(reduceMotion: Bool) -> Bool { !reduceMotion }

    /// Confetti draws nothing under Reduce Motion.
    public static func celebrationBursts(reduceMotion: Bool) -> Bool { !reduceMotion }
}

/// How a new message enters a conversation. Your own send pops up from the composer corner on
/// `MotionSpec.sendPop`; someone else's glides up and fades in on the layout spring. History and
/// Reduce Motion arrive at rest.
public enum BubbleArrival {
    /// Own sends start a little small so the pop reads.
    public static let sendStartScale = 0.82
    public static let minAlpha = 0.35
    /// The spring may overshoot 1 for a moment; the bubble lifts a hair past rest and settles.
    public static let maxOvershoot = 0.15
    /// How far below its place an arriving bubble starts, in points.
    public static let offset = 18.0

    public struct Frame: Equatable, Sendable {
        public let scale: Double
        /// A share of `offset`: 1 at the start, 0 at rest.
        public let offsetFraction: Double
        public let alpha: Double
    }

    public static func frame(progress: Double, mine: Bool) -> Frame {
        let settled = min(1 + maxOvershoot, max(0, progress))
        let scale = mine ? sendStartScale + (1 - sendStartScale) * settled : 1
        let alpha = min(1, max(0, minAlpha + (1 - minAlpha) * settled))
        return Frame(scale: scale, offsetFraction: 1 - settled, alpha: alpha)
    }
}
