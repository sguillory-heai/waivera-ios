import Foundation

/// Where a row's leading tile or avatar sits (v7, item 1, and its follow-up): centred while the
/// row's content is no taller than a standard two-line row, and pinned `Spacing.leadingTileTop`
/// below the content's top once long content makes it taller, so the tile stays level with the
/// title's first line. Decided on measured heights, never on a count of lines.
public enum LeadingTileAlignment {
    /// Half a subtitle line of slack, so rounding or a slightly taller style never tips a
    /// two-line row over; a third line adds a whole line and always crosses it.
    public static let twoLineSlackLines = 0.5

    /// The tallest content a standard two-line row has: a title line, the 2pt gap and a subtitle
    /// line, plus half a subtitle line, at the current text size.
    public static func twoLineRowContentHeight(titleLine: Double, gap: Double, subtitleLine: Double) -> Double {
        (titleLine + gap + subtitleLine * (1 + twoLineSlackLines)).rounded()
    }

    /// The tile's offset from the top of the row's content.
    /// - Parameters:
    ///   - tileHeight: the leading view's height.
    ///   - contentHeight: the height of the row's content (the tallest of its children).
    ///   - standardHeight: `twoLineRowContentHeight` at the current text size.
    ///   - topPin: `Spacing.leadingTileTop`.
    public static func offset(
        tileHeight: Double,
        contentHeight: Double,
        standardHeight: Double,
        topPin: Double = Double(Spacing.leadingTileTop)
    ) -> Double {
        let centred = ((contentHeight - tileHeight) / 2).rounded()
        return contentHeight > standardHeight ? min(centred, topPin) : centred
    }

    /// Whether the tile is pinned to the top for these heights.
    public static func isPinned(contentHeight: Double, standardHeight: Double) -> Bool {
        contentHeight > standardHeight
    }
}

/// How segments share a segmented control's row (Android UI2-25): equal while the widest segment
/// fits its equal share, proportional to their own widths while all fit, else the row scrolls.
public enum SegmentFit: Equatable, Sendable {
    case equal
    case proportional([Double])
    case scroll

    public static func fit(segmentWidths: [Double], available: Double) -> SegmentFit {
        guard let widest = segmentWidths.max() else { return .equal }
        if widest * Double(segmentWidths.count) <= available { return .equal }
        if segmentWidths.reduce(0, +) <= available { return .proportional(segmentWidths.map { max($0, 1) }) }
        return .scroll
    }
}

/// When a banner's text action moves under the text instead of sitting beside it (Android UI4-06).
public enum BannerLayoutRule {
    public static let inlineActionMaxFraction = 0.35
    public static let inlineMessageMaxLines = 2

    public static func actionStacks(
        category: TextSizeCategory,
        actionWidth: Double,
        availableWidth: Double,
        messageLinesBeside: Int = 1
    ) -> Bool {
        TypeScale.isLarge(category)
            || actionWidth > availableWidth * inlineActionMaxFraction
            || messageLinesBeside > inlineMessageMaxLines
    }
}

/// How many lines a person's name may take where it is a headline (wave 29 N4/N5).
public enum NameLines {
    /// A list row's name: 1 line, 2 above 130%.
    public static func listRow(_ category: TextSizeCategory) -> Int { TypeScale.isLarge(category) ? 2 : 1 }

    /// A profile or person hero's name: 2 lines, 3 above 130%.
    public static func hero(_ category: TextSizeCategory) -> Int { TypeScale.isLarge(category) ? 3 : 2 }

    /// The Today greeting and the reward line's first name: 2 lines.
    public static let greeting = 2

    /// A celebration card's or banner's name: 2 lines.
    public static let celebration = 2

    /// A bookmark author: 1 line, 2 above 130%.
    public static func bookmarkAuthor(_ category: TextSizeCategory) -> Int { listRow(category) }
}
