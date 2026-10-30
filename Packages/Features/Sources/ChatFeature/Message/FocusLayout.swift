import Foundation
import WaiveraDesign

/// How the focus overlay arranges the lifted bubble and its menu (Android `MessageFocusLayout`).
enum FocusArrangement: Hashable, Sendable {
    /// Reactions above the bubble, the menu under it: a phone held upright.
    case stacked
    /// Reactions above the bubble, the menu in a column beside them: a short window, such as a
    /// phone in landscape, where the menu does not fit under even a two-line bubble.
    case beside
}

/// Everything the focus overlay's placement depends on, in the overlay's own points. `safe` is
/// the window less the system bars and the keyboard, and less a margin; nothing is placed outside
/// it. `anchor` is where the pressed bubble sits, or `nil` when it is not known (a preview).
/// `pill` is `nil` when the person cannot react.
struct FocusGeometry: Hashable, Sendable {
    var safe: CGRect
    var anchor: CGRect?
    var mine: Bool
    var pill: CGSize?
    var menu: CGSize
    var gap: CGFloat
    var minBubbleHeight: CGFloat
    var maxBubbleHeight: CGFloat
    var minBubbleWidth: CGFloat
    var fallbackBubbleWidth: CGFloat
}

/// The arrangement and the most room the lifted bubble may take in it.
struct FocusFrame: Hashable, Sendable {
    var arrangement: FocusArrangement
    var bubbleMaxWidth: CGFloat
    var bubbleMaxHeight: CGFloat
}

/// Where each piece's top-leading corner goes.
struct FocusPlacement: Hashable, Sendable {
    var arrangement: FocusArrangement
    var bubble: CGPoint
    var pill: CGPoint?
    var menu: CGPoint
}

/// One frame of the overlay's entrance. See `FocusGeometry.liftFrame`.
struct LiftFrame: Hashable, Sendable {
    var bubbleScale: CGFloat
    var bubbleShift: CGFloat
    var pillShift: CGFloat
    var menuShift: CGFloat
}

extension FocusGeometry {
    /// The width the action menu is measured at: its token width, never wider than the safe
    /// area. When the window is wide enough for the menu to sit beside the reaction pill
    /// (landscape), it is held to that room, so the beside column never runs under the pill.
    static func menuWidth(
        safeWidth: CGFloat,
        pillWidth: CGFloat,
        gap: CGFloat,
        target: CGFloat,
        minBeside: CGFloat
    ) -> CGFloat {
        let besideRoom = safeWidth - pillWidth - gap
        return besideRoom >= minBeside ? min(target, besideRoom) : min(target, safeWidth)
    }

    /// The tallest the menu may be. It keeps its full size whenever it fits with the reactions
    /// and a two-line bubble (the bubble gives way first); only past that, at the largest text
    /// on a small phone, does it scroll inside itself so Delete is still reachable.
    static func menuMaxHeight(
        safeHeight: CGFloat,
        pillHeight: CGFloat?,
        gap: CGFloat,
        minBubbleHeight: CGFloat
    ) -> CGFloat {
        let pillBlock = pillHeight.map { $0 + gap } ?? 0
        return max(minBubbleHeight, safeHeight - pillBlock - gap - minBubbleHeight)
    }

    /// Picks the arrangement. The menu and the reactions always keep their size: when room is
    /// short it is the bubble that gives way, clamped to less of its height (wave 28 B1). Under
    /// it the bubble keeps at least `minBubbleHeight`; when even that does not fit, the menu moves
    /// beside the bubble.
    func frame() -> FocusFrame {
        let pillBlock = pill.map { $0.height + gap } ?? 0
        let width = anchor?.width ?? fallbackBubbleWidth
        let cap = max(maxBubbleHeight, minBubbleHeight)
        let stackedRoom = safe.height - pillBlock - gap - menu.height
        let column = safe.width - menu.width - gap
        let besideFits = column >= max(minBubbleWidth, pill?.width ?? 0) && menu.height <= safe.height
        if stackedRoom >= minBubbleHeight {
            return FocusFrame(
                arrangement: .stacked,
                bubbleMaxWidth: min(width, safe.width),
                bubbleMaxHeight: min(stackedRoom, cap)
            )
        }
        if besideFits {
            return FocusFrame(
                arrangement: .beside,
                bubbleMaxWidth: min(width, column),
                bubbleMaxHeight: min(safe.height - pillBlock, cap)
            )
        }
        // Neither fits (a split-screen sliver): the smallest bubble, the menu under it.
        return FocusFrame(
            arrangement: .stacked,
            bubbleMaxWidth: min(width, safe.width),
            bubbleMaxHeight: minBubbleHeight
        )
    }

    /// Places the pieces once the bubble is measured. The bubble starts where it was pressed and
    /// moves only as far as it must for the reactions and the menu to fit inside the safe area:
    /// up when it sat near the composer, down when its top had scrolled under the bar. The
    /// reactions and the menu line up with the bubble's own side.
    func place(_ frame: FocusFrame, bubble: CGSize) -> FocusPlacement {
        let pillBlock = pill.map { $0.height + gap } ?? 0
        switch frame.arrangement {
        case .stacked:
            let left = bubbleLeft(columnLeft: safe.minX, columnRight: safe.maxX, width: bubble.width)
            let right = left + bubble.width
            let desiredTop = anchor?.minY ?? (safe.maxY - menu.height - gap - bubble.height)
            let groupTop = clampTop(desiredTop - pillBlock, height: pillBlock + bubble.height + gap + menu.height)
            let bubbleTop = groupTop + pillBlock
            return FocusPlacement(
                arrangement: .stacked,
                bubble: CGPoint(x: left, y: bubbleTop),
                pill: pill.map {
                    CGPoint(
                        x: sideAligned($0.width, left: left, right: right, minLeft: safe.minX, maxRight: safe.maxX),
                        y: groupTop
                    )
                },
                menu: CGPoint(
                    x: sideAligned(menu.width, left: left, right: right, minLeft: safe.minX, maxRight: safe.maxX),
                    y: bubbleTop + bubble.height + gap
                )
            )
        case .beside:
            let columnWidth = safe.width - menu.width - gap
            let columnLeft = mine ? safe.maxX - columnWidth : safe.minX
            let columnRight = columnLeft + columnWidth
            let menuLeft = mine ? safe.minX : columnRight + gap
            let left = bubbleLeft(columnLeft: columnLeft, columnRight: columnRight, width: bubble.width)
            let right = left + bubble.width
            let desiredTop = anchor?.minY ?? (safe.maxY - bubble.height)
            let groupTop = clampTop(desiredTop - pillBlock, height: pillBlock + bubble.height)
            let bubbleTop = groupTop + pillBlock
            return FocusPlacement(
                arrangement: .beside,
                bubble: CGPoint(x: left, y: bubbleTop),
                pill: pill.map {
                    CGPoint(
                        x: sideAligned($0.width, left: left, right: right, minLeft: columnLeft, maxRight: columnRight),
                        y: groupTop
                    )
                },
                menu: CGPoint(x: menuLeft, y: clampTop(bubbleTop, height: menu.height))
            )
        }
    }

    /// One frame of the entrance, from the lift spring's `progress` (0 at the press, 1 at rest,
    /// past 1 while it overshoots). The bubble scales about its centre from `from` and moves from
    /// `travel` points below its place (above it when negative).
    ///
    /// The pill and the menu ride the bubble's edges so the spring can never carry the bubble
    /// under them (wave 30 O1): when the bubble's drawn top is above its resting top the pill
    /// moves up by as much; when its drawn bottom is below its resting bottom the menu under it
    /// moves down by as much (stacked only). At rest nothing is shifted.
    static func liftFrame(
        progress: CGFloat,
        from: CGFloat,
        travel: CGFloat,
        bubbleHeight: CGFloat,
        menuFollows: Bool
    ) -> LiftFrame {
        let scale = from + (1 - from) * progress
        let shift = travel * (1 - progress)
        // Scaled about its centre, each edge moves in by half the height it loses.
        let inset = bubbleHeight * (1 - scale) / 2
        return LiftFrame(
            bubbleScale: scale,
            bubbleShift: shift,
            pillShift: min(0, shift + inset),
            menuShift: menuFollows ? max(0, shift - inset) : 0
        )
    }

    /// `top` moved just enough for `height` to sit inside the safe area; the top wins if neither fits.
    private func clampTop(_ top: CGFloat, height: CGFloat) -> CGFloat {
        max(safe.minY, min(top, safe.maxY - height))
    }

    /// The bubble where it was pressed, kept inside the column.
    private func bubbleLeft(columnLeft: CGFloat, columnRight: CGFloat, width: CGFloat) -> CGFloat {
        let desired = anchor?.minX ?? (mine ? columnRight - width : columnLeft)
        return max(columnLeft, min(desired, columnRight - width))
    }

    /// A piece of `width` lined up with the bubble's own side, kept inside `minLeft...maxRight`.
    private func sideAligned(_ width: CGFloat, left: CGFloat, right: CGFloat, minLeft: CGFloat, maxRight: CGFloat)
        -> CGFloat
    {
        let desired = mine ? right - width : left
        return max(minLeft, min(desired, maxRight - width))
    }
}

/// Which fades a clamped lifted bubble shows (v7 item 2): the bottom one while it can scroll on,
/// the top one once its start has scrolled away. A message that fits shows neither.
struct FocusFades: Hashable, Sendable {
    var top: Bool
    var bottom: Bool

    init(top: Bool, bottom: Bool) {
        self.top = top
        self.bottom = bottom
    }

    /// `offset` is how far the content has scrolled (0 at the start).
    init(contentHeight: CGFloat, viewportHeight: CGFloat, offset: CGFloat) {
        let tolerance = ChatMetrics.scrollEdgeTolerance
        let overflow = contentHeight - viewportHeight
        top = overflow > tolerance && offset > tolerance
        bottom = overflow > tolerance && offset < overflow - tolerance
    }
}

/// How the overlay arrives. With motion on, the bubble starts at the long press's sink where it
/// was pressed and lifts to its place on the bouncy pop spring, while the pill and the menu scale
/// out of its edge and fade in. With Reduce Motion nothing moves or scales: the overlay only
/// fades in (150ms), the bubble with it.
struct FocusEntrance: Equatable, Sendable {
    var bubbleFrom: CGFloat
    var piecesFrom: CGFloat
    var travels: Bool
    var bubbleFades: Bool
    /// The lift's spring; `nil` snaps to rest.
    var lift: SpringSpec?
    var fade: MotionCurve

    init(reduceMotion: Bool) {
        if reduceMotion {
            bubbleFrom = 1
            piecesFrom = 1
            travels = false
            bubbleFades = true
            lift = nil
        } else {
            bubbleFrom = MotionPolicy.longPressScale(.button, reduceMotion: false)
            piecesFrom = MotionTiming.popStartScale
            travels = true
            bubbleFades = false
            lift = MotionSpec.pop
        }
        fade = MotionPolicy.curve(for: .state, reduceMotion: reduceMotion)
    }
}
