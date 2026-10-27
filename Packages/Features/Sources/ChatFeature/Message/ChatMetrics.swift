import Foundation

/// Chat-only sizes from the reference screens (03 §6, §8, §13), named once so views carry no
/// literal numbers. Anything other features need belongs in WaiveraDesign instead.
enum ChatMetrics {
    static let bubbleRadius: CGFloat = 15
    static let bubbleGroupedRadius: CGFloat = 6
    static let bubbleMinWidth: CGFloat = 54
    static let bubbleMaxWidthFraction: CGFloat = 0.82
    static let avatarTopOffset: CGFloat = 18
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
}
