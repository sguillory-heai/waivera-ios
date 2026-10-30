import Foundation
import WaiveraDesign

/// Chat-only sizes from the reference screens (03 §6, §8, §13), named once so views carry no
/// literal numbers. Anything other features need belongs in WaiveraDesign instead.
enum ChatMetrics {
    static let bubbleRadius: CGFloat = 15
    static let bubbleGroupedRadius: CGFloat = 6
    static let bubbleMinWidth: CGFloat = 54
    static let bubbleMaxWidthFraction: CGFloat = 0.82
    static let avatarTopOffset: CGFloat = 18
    /// How far an author avatar's touch area reaches past its 32pt square, to make 44pt.
    static let avatarHitOutset: CGFloat = (ControlSize.minHitTarget - ControlSize.avatarSmall) / 2
    static let imageWidth: CGFloat = 250
    static let imageHeight: CGFloat = 190
    static let imageRadius: CGFloat = 13
    static let fileCardWidth: CGFloat = 250
    static let reactionPillHeight: CGFloat = 30
    static let typingSlot: CGFloat = 22
    static let composerMaxLines = 6
    static let stagedThumbnail: CGFloat = 50
    static let readOnlyTile: CGFloat = 34
    static let liveDot: CGFloat = 7
    static let skeletonBubbleHeight: CGFloat = 54
    static let skeletonWidthFractions: [CGFloat] = [0.66, 0.51, 0.78, 0.62, 0.47]
    static let arrivalOffset: CGFloat = 18
    static let arrivalMinOpacity = 0.35
    static let previewMaxHeight: CGFloat = 220
    static let emojiTarget: CGFloat = 48
    static let reactionTabMinWidth: CGFloat = 62
    static let tableCellWidth: CGFloat = 150
    /// Farther than this from the newest message shows "Jump to latest" (03 §15).
    static let jumpToLatestThreshold: CGFloat = 180
    /// Within this of the newest message, new rows keep the list pinned to the bottom.
    static let stickToBottomThreshold: CGFloat = 48
    /// How often relative times ("2 minutes ago") refresh while the list is on screen (03 §4).
    static let timeTick: TimeInterval = 30
    static let maxZoom: CGFloat = 5
    static let doubleTapZoom: CGFloat = 2.5
    static let savedPopStart: CGFloat = 0.75
    static let halfTurnDegrees: Double = 180
    /// Pixels per point when decoding thumbnails; the largest device scale.
    static let decodeScale: CGFloat = 3

    // MARK: Focus overlay (spec §9.1, Android `ChatDimens.Focus*`)

    /// The reaction pill: six 48pt targets, 4pt apart, inside 4pt of padding (316pt, which fits a
    /// 360pt-wide phone's two gutters). The emoji keep 26pt at any text size (wave 28 B2).
    static let focusPillPadding: CGFloat = Spacing.extraSmall
    static let focusPillGap: CGFloat = Spacing.extraSmall
    static let focusEmojiGlyph: CGFloat = 26
    /// The menu's width up to large text, and above it; never wider than the safe area.
    static let focusMenuWidth: CGFloat = 232
    static let focusMenuWidthLarge: CGFloat = 320
    /// The narrowest menu worth putting beside the bubble (landscape) instead of under it.
    static let focusMenuMinWidth: CGFloat = 200
    /// Space between the pill, the bubble and the menu, and the margin inside the safe area.
    static let focusGap: CGFloat = Spacing.small
    /// The least of a lifted bubble that still shows: about two lines of body text.
    static let focusMinBubble: CGFloat = 56
    static let focusMinBubbleWidth: CGFloat = 160
    /// The lifted bubble's tallest, as a share of the safe height.
    static let focusBubbleMaxFraction: CGFloat = 0.42
    /// A clamped lifted bubble's fades cover about this many lines of body text.
    static let focusFadeLines: CGFloat = 2
    /// The share of a fade, from its edge, that is the solid fill.
    static let focusFadeSolidStop: CGFloat = 0.2
    /// How long Copy's check and "Copied" show before the overlay closes on its own.
    static let focusCopiedHold: TimeInterval = MotionTiming.syncedBeat
    /// Scroll offsets within this of an edge count as at the edge.
    static let scrollEdgeTolerance: CGFloat = 0.5
}
