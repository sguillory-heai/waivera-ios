#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    enum FocusPart: Hashable, Sendable {
        case pill, bubble, menu
    }

    struct FocusPartKey: LayoutValueKey {
        static let defaultValue = FocusPart.bubble
    }

    /// Places the pill, the bubble and the menu with `FocusGeometry`, and rides the pill and the
    /// menu on the bubble's edges through the lift (`liftFrame`). `progress` animates with the
    /// lift spring; the bubble's own scale animates beside it in the same transaction.
    struct FocusOverlayLayout: Layout {
        var safe: CGRect
        var anchor: CGRect?
        var mine: Bool
        var menuTarget: CGFloat
        var progress: CGFloat
        var entrance: FocusEntrance

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            proposal.replacingUnspecifiedDimensions()
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            let pill = subviews.first { $0[FocusPartKey.self] == .pill }
            guard let bubble = subviews.first(where: { $0[FocusPartKey.self] == .bubble }),
                let menu = subviews.first(where: { $0[FocusPartKey.self] == .menu })
            else { return }
            let pillSize = pill?.sizeThatFits(ProposedViewSize(width: safe.width, height: nil))
            let geometry = geometry(pill: pillSize, menu: menu)
            let frame = geometry.frame()
            let bubbleIdeal = bubble.sizeThatFits(ProposedViewSize(width: frame.bubbleMaxWidth, height: nil))
            let bubbleSize = CGSize(
                width: min(bubbleIdeal.width, frame.bubbleMaxWidth),
                height: min(bubbleIdeal.height, frame.bubbleMaxHeight)
            )
            let placed = geometry.place(frame, bubble: bubbleSize)
            let travel = entrance.travels ? (anchor?.minY ?? placed.bubble.y) - placed.bubble.y : 0
            let lift = FocusGeometry.liftFrame(
                progress: progress,
                from: entrance.bubbleFrom,
                travel: travel,
                bubbleHeight: bubbleSize.height,
                menuFollows: placed.arrangement == .stacked
            )
            let origin = bounds.origin
            bubble.place(
                at: CGPoint(x: origin.x + placed.bubble.x, y: origin.y + placed.bubble.y + lift.bubbleShift),
                anchor: .topLeading,
                proposal: ProposedViewSize(bubbleSize)
            )
            if let pill, let pillSize, let pillOrigin = placed.pill {
                pill.place(
                    at: CGPoint(x: origin.x + pillOrigin.x, y: origin.y + pillOrigin.y + lift.pillShift),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(pillSize)
                )
            }
            menu.place(
                at: CGPoint(x: origin.x + placed.menu.x, y: origin.y + placed.menu.y + lift.menuShift),
                anchor: .topLeading,
                proposal: ProposedViewSize(geometry.menu)
            )
        }

        /// The menu is measured at its token width (held beside the pill when the window is wide)
        /// and capped so that, at the largest text, it scrolls instead of leaving the screen.
        private func geometry(pill: CGSize?, menu: LayoutSubview) -> FocusGeometry {
            let gap = ChatMetrics.focusGap
            let menuWidth = FocusGeometry.menuWidth(
                safeWidth: safe.width,
                pillWidth: pill?.width ?? 0,
                gap: gap,
                target: menuTarget,
                minBeside: ChatMetrics.focusMenuMinWidth
            )
            let menuCap = FocusGeometry.menuMaxHeight(
                safeHeight: safe.height,
                pillHeight: pill?.height,
                gap: gap,
                minBubbleHeight: ChatMetrics.focusMinBubble
            )
            let menuIdeal = menu.sizeThatFits(ProposedViewSize(width: menuWidth, height: nil))
            return FocusGeometry(
                safe: safe,
                anchor: anchor,
                mine: mine,
                pill: pill,
                menu: CGSize(width: menuWidth, height: min(menuIdeal.height, menuCap)),
                gap: gap,
                minBubbleHeight: ChatMetrics.focusMinBubble,
                maxBubbleHeight: (safe.height * ChatMetrics.focusBubbleMaxFraction).rounded(.down),
                minBubbleWidth: ChatMetrics.focusMinBubbleWidth,
                fallbackBubbleWidth: (safe.width * ChatMetrics.bubbleMaxWidthFraction).rounded(.down)
            )
        }
    }

    /// Where the pressed bubble was when its long press fired, so the overlay lifts that bubble
    /// where it is. One per screen; plain values, not state, because nothing redraws from it.
    @MainActor
    final class FocusAnchors {
        private var lastMessageId: Int?
        private var lastBounds: CGRect?

        func record(_ messageId: Int, bounds: CGRect?) {
            lastMessageId = bounds == nil ? nil : messageId
            lastBounds = bounds
        }

        func bounds(of messageId: Int) -> CGRect? {
            lastMessageId == messageId ? lastBounds : nil
        }
    }

    /// A view's latest global frame, kept without state so a press can ask where it is.
    @MainActor
    final class AnchorBox {
        var frame: CGRect?
    }
#endif
