import Foundation

/// Where a name sits in a headline ("Good morning, Maria-Fernanda") it may wrap only between
/// words (wave 29 N2). When the widest single word is wider than the line, the text keeps to
/// one line and ends in "…" instead of breaking inside the word.
enum WordFit {
    /// The words of `text`, split at spaces and no-break spaces, as a line can break between them.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" || $0.isNewline }).map(String.init)
    }

    /// Whether `text` may wrap: every word fits the line on its own.
    static func wraps(widestWord: Double, lineWidth: Double) -> Bool {
        lineWidth <= 0 || widestWord <= lineWidth
    }

    /// Whether the stat tiles give way to the stacked card: a label word would break inside
    /// itself in a tile (UI10-04), or the text is extra large on a phone-width hero (UI10-08).
    static func statsStack(
        widestLabelWord: Double,
        width: Double,
        tiles: Int,
        extraLargeText: Bool,
        metrics: StatTileMetrics
    ) -> Bool {
        guard width > 0, tiles > 0 else { return false }
        let tileLabel = (width - metrics.gap * Double(tiles - 1)) / Double(tiles) - metrics.tilePadding * 2
        return widestLabelWord > tileLabel || (extraLargeText && width < metrics.stackMaxWidth)
    }
}

/// The stat row's spacing: the gap between tiles, a tile's side padding and the widest hero
/// that stacks at extra-large text.
struct StatTileMetrics: Equatable, Sendable {
    var gap: Double
    var tilePadding: Double
    var stackMaxWidth: Double
}
