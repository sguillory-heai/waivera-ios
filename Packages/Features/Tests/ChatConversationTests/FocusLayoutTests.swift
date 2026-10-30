import Foundation
import Testing
import WaiveraDesign

@testable import ChatFeature

/// The focus overlay's placement and entrance as plain functions (Android
/// `MessageFocusLayoutTest`): a 360x640 phone upright and on its side, with the menu sizes the
/// default and the largest text give.
@Suite("Focus overlay layout")
struct FocusLayoutTests {
    private let gap: CGFloat = 8
    private let pill = CGSize(width: 316, height: 56)
    private let menuDefault = CGSize(width: 232, height: 257)
    private let menuLarge = CGSize(width: 320, height: 300)

    private func geometry(
        window: CGSize,
        menu: CGSize,
        anchor: CGRect?,
        mine: Bool = true,
        pill: CGSize?? = .none
    ) -> FocusGeometry {
        let safe = CGRect(x: 16, y: 24 + gap, width: window.width - 32, height: window.height - 48 - gap - 24 - gap)
        return FocusGeometry(
            safe: safe,
            anchor: anchor,
            mine: mine,
            pill: pill ?? self.pill,
            menu: menu,
            gap: gap,
            minBubbleHeight: ChatMetrics.focusMinBubble,
            maxBubbleHeight: (safe.height * ChatMetrics.focusBubbleMaxFraction).rounded(.down),
            minBubbleWidth: ChatMetrics.focusMinBubbleWidth,
            fallbackBubbleWidth: 270
        )
    }

    /// Lays out a bubble as tall as it can be and checks nothing leaves the safe area or overlaps.
    @discardableResult
    private func expectFits(_ geometry: FocusGeometry, naturalHeight: CGFloat, _ label: String) -> FocusPlacement {
        let frame = geometry.frame()
        let bubble = CGSize(width: frame.bubbleMaxWidth, height: min(naturalHeight, frame.bubbleMaxHeight))
        let placed = geometry.place(frame, bubble: bubble)
        var rects: [(String, CGRect)] = [
            ("bubble", CGRect(origin: placed.bubble, size: bubble)),
            ("menu", CGRect(origin: placed.menu, size: geometry.menu)),
        ]
        if let origin = placed.pill, let size = geometry.pill {
            rects.append(("pill", CGRect(origin: origin, size: size)))
        }
        for (name, rect) in rects {
            #expect(geometry.safe.contains(rect), "\(label): the \(name) \(rect) leaves the safe area \(geometry.safe)")
        }
        for first in rects.indices {
            for second in rects.indices where second > first {
                let overlap = rects[first].1.intersection(rects[second].1)
                #expect(
                    overlap.isNull || overlap.width <= 0 || overlap.height <= 0,
                    "\(label): the \(rects[first].0) overlaps the \(rects[second].0)"
                )
            }
        }
        return placed
    }

    @Test func anUprightPhoneStacksTheMenuUnderTheBubble() {
        let near = CGRect(x: 120, y: 500, width: 224, height: 40)
        let layout = geometry(window: CGSize(width: 360, height: 640), menu: menuDefault, anchor: near)
        #expect(layout.frame().arrangement == .stacked)
        let placed = expectFits(layout, naturalHeight: 40, "short")
        #expect(placed.bubble.y < near.minY, "a bubble by the composer moves up so the menu fits")
        #expect(placed.menu.x == near.maxX - menuDefault.width, "the menu lines up with my bubble's end")
    }

    @Test func aLongMessageIsClampedSoTheMenuNeverLeavesTheScreen() {
        let tall = CGRect(x: 48, y: -640, width: 296, height: 1190)
        for menu in [menuDefault, menuLarge] {
            let layout = geometry(window: CGSize(width: 360, height: 640), menu: menu, anchor: tall)
            let frame = layout.frame()
            #expect(frame.arrangement == .stacked)
            #expect(frame.bubbleMaxHeight < 640, "the bubble is clamped")
            #expect(frame.bubbleMaxHeight <= layout.safe.height * ChatMetrics.focusBubbleMaxFraction)
            let placed = expectFits(layout, naturalHeight: 6000, "3,000 characters")
            #expect(placed.pill?.y == layout.safe.minY, "the bubble opens at its start, at the top")
        }
    }

    @Test func landscapePutsTheMenuBesideTheBubble() {
        for menu in [CGSize(width: 232, height: 257), CGSize(width: 280, height: 265)] {
            let window = CGSize(width: 640, height: 360)
            let layout = geometry(window: window, menu: menu, anchor: CGRect(x: 300, y: 200, width: 308, height: 60))
            #expect(layout.frame().arrangement == .beside)
            expectFits(layout, naturalHeight: 6000, "landscape long")
            expectFits(layout, naturalHeight: 40, "landscape short")
            let theirs = geometry(
                window: window,
                menu: menu,
                anchor: CGRect(x: 56, y: 200, width: 244, height: 60),
                mine: false
            )
            expectFits(theirs, naturalHeight: 400, "landscape theirs")
        }
    }

    @Test func theMenuIsHeldBesideThePillWhenTheWindowIsWide() {
        func width(_ safe: CGFloat, _ target: CGFloat) -> CGFloat {
            FocusGeometry.menuWidth(safeWidth: safe, pillWidth: 316, gap: gap, target: target, minBeside: 200)
        }
        #expect(width(608, 232) == 232)
        #expect(width(608, 320) == 284)
        #expect(width(328, 320) == 320)
        #expect(width(328, 232) == 232)
    }

    @Test func withoutReactionsThereIsNoPill() {
        let layout = geometry(
            window: CGSize(width: 360, height: 640),
            menu: menuDefault,
            anchor: CGRect(x: 16, y: 300, width: 244, height: 60),
            mine: false,
            pill: .some(nil)
        )
        let placed = expectFits(layout, naturalHeight: 60, "read-only")
        #expect(placed.pill == nil)
        #expect(placed.bubble.x == 16, "someone else's bubble keeps its start")
    }

    /// At the largest text on a small phone the menu never pushes Delete off screen: past the
    /// room left by the reactions and a two-line bubble, it scrolls inside itself.
    @Test func aMenuTallerThanTheRoomIsCappedSoEveryActionStaysReachable() {
        // iPhone SE (375x667), the smallest phone iOS 17 runs on, at the largest text.
        let window = CGSize(width: 375, height: 667)
        var layout = geometry(window: window, menu: .zero, anchor: CGRect(x: 40, y: 300, width: 300, height: 80))
        let cap = FocusGeometry.menuMaxHeight(
            safeHeight: layout.safe.height,
            pillHeight: pill.height,
            gap: gap,
            minBubbleHeight: ChatMetrics.focusMinBubble
        )
        #expect(cap + pill.height + ChatMetrics.focusMinBubble + gap * 2 <= layout.safe.height)
        layout.menu = CGSize(width: layout.safe.width, height: min(900, cap))
        #expect(layout.frame().arrangement == .stacked)
        expectFits(layout, naturalHeight: 80, "capped menu")
    }

    @Test func reducedMotionOnlyFades() {
        let reduced = FocusEntrance(reduceMotion: true)
        #expect(reduced.bubbleFrom == 1)
        #expect(reduced.piecesFrom == 1)
        #expect(!reduced.travels)
        #expect(reduced.bubbleFades)
        #expect(reduced.lift == nil)
        #expect(reduced.fade == .tween(MotionSpec.reducedFade))
    }

    @Test func withMotionTheBubbleLiftsFromItsSinkOnThePopSpring() {
        let standard = FocusEntrance(reduceMotion: false)
        #expect(abs(standard.bubbleFrom - PressDepth.button.longPressScale) < 0.000_1)
        #expect(standard.travels)
        #expect(!standard.bubbleFades)
        #expect(standard.piecesFrom < 1)
        #expect(standard.lift == MotionSpec.pop)
    }

    /// Wave 30 O1: at every 16ms frame of the pop spring, the pill stays at least the gap above
    /// the bubble's drawn top and, stacked, the menu at least the gap below its drawn bottom.
    @Test func theSpringNeverCarriesTheBubbleUnderThePillOrTheMenu() {
        let entrance = FocusEntrance(reduceMotion: false)
        let frames = Self.springFrames(MotionSpec.pop)
        #expect(frames.contains { $0 > 1 }, "the pop spring overshoots, so this checks something")
        for travel: CGFloat in [260, 40, -640, 0] {
            for height: CGFloat in [40, 268] {
                for stacked in [true, false] {
                    for progress in frames {
                        let frame = FocusGeometry.liftFrame(
                            progress: progress,
                            from: entrance.bubbleFrom,
                            travel: travel,
                            bubbleHeight: height,
                            menuFollows: stacked
                        )
                        expectClear(frame, height: height, stacked: stacked)
                    }
                    let rest = FocusGeometry.liftFrame(
                        progress: 1,
                        from: entrance.bubbleFrom,
                        travel: travel,
                        bubbleHeight: height,
                        menuFollows: stacked
                    )
                    #expect(rest == LiftFrame(bubbleScale: 1, bubbleShift: 0, pillShift: 0, menuShift: 0))
                }
            }
        }
    }

    @Test func clampedBubbleFadesFollowTheScroll() {
        #expect(FocusFades(contentHeight: 80, viewportHeight: 80, offset: 0) == FocusFades(top: false, bottom: false))
        #expect(FocusFades(contentHeight: 600, viewportHeight: 200, offset: 0) == FocusFades(top: false, bottom: true))
        #expect(FocusFades(contentHeight: 600, viewportHeight: 200, offset: 120) == FocusFades(top: true, bottom: true))
        #expect(
            FocusFades(contentHeight: 600, viewportHeight: 200, offset: 400) == FocusFades(top: true, bottom: false)
        )
    }

    private func expectClear(_ frame: LiftFrame, height: CGFloat, stacked: Bool) {
        let restTop: CGFloat = 300
        let epsilon: CGFloat = 0.01
        let inset = height * (1 - frame.bubbleScale) / 2
        let drawnTop = restTop + frame.bubbleShift + inset
        let drawnBottom = restTop + height + frame.bubbleShift - inset
        let pillBottom = restTop - gap + frame.pillShift
        #expect(drawnTop - pillBottom >= gap - epsilon)
        if stacked {
            let menuTop = restTop + height + gap + frame.menuShift
            #expect(menuTop - drawnBottom >= gap - epsilon)
        } else {
            #expect(abs(frame.menuShift) < epsilon)
        }
    }

    /// The spring's value from 0 toward 1 every 16ms until it settles (unit mass).
    private static func springFrames(_ spec: SpringSpec) -> [CGFloat] {
        let omega = spec.stiffness.squareRoot()
        let zeta = spec.dampingRatio
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return stride(from: 0.0, through: 1.0, by: 0.016).map { time in
            let envelope = exp(-zeta * omega * time)
            let value = 1 - envelope * (cos(damped * time) + zeta * omega / damped * sin(damped * time))
            return CGFloat(value)
        }
    }
}
