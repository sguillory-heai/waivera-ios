import Foundation

/// How a one-line name fits (v7, item 3): it may shrink to `minimumScale` of its style's size,
/// in `step` steps, before it ends in "…". About 15% smaller is the most the owner accepts.
public enum NameFit {
    /// SwiftUI `minimumScaleFactor` for a one-line chat name.
    public static let minimumScale = 0.85
    /// Android's auto-size step, in points.
    public static let step = 0.25
    public static let ellipsis = "…"
    /// A no-break space, so "+4" never parts from the name before it.
    public static let compactGap = "\u{00A0}"

    /// The sizes a name may be drawn at, largest first: the full size, then each step down from
    /// under the full size to the floor.
    public static func sizes(full: Double) -> [Double] {
        let floor = full * minimumScale
        var steps: [Double] = []
        var size = floor
        while size < full - 0.001 {
            steps.append(size)
            size += step
        }
        return [full] + steps.reversed()
    }
}

/// What a shortened one-line title shows, and the size it is drawn at.
public struct ShortenedName: Equatable, Sendable {
    public let shown: String
    public let size: Double

    public init(shown: String, size: Double) {
        self.shown = shown
        self.size = size
    }
}

/// A one-line title composed around a name, such as a group's "Maria-Fernanda R. & 4 others"
/// (v7 follow-up, item 4). Full size when it fits, then the size steps down to the floor; past
/// that only the name ends in "…", so the count around it always shows. When not even "…" and the
/// count fit, the name and the compact suffix ("+4") are tried the same way before the whole
/// title is left for the text's own tail truncation at the floor size.
public enum ShortenedNameFitter {
    /// - Parameters:
    ///   - text: the whole title.
    ///   - shortenable: the name's range in `text` (character offsets); the only part that may be cut.
    ///   - fullSize: the style's size in points.
    ///   - compactSuffix: the short count ("+4"), or nil.
    ///   - fits: whether a candidate string fits the line at a size.
    public static func fit(
        text: String,
        shortenable: Range<Int>,
        fullSize: Double,
        compactSuffix: String? = nil,
        fits: (String, Double) -> Bool
    ) -> ShortenedName {
        let floor = fullSize * NameFit.minimumScale
        if let size = NameFit.sizes(full: fullSize).first(where: { fits(text, $0) }) {
            return ShortenedName(shown: text, size: size)
        }
        let characters = Array(text)
        guard shortenable.lowerBound >= 0, shortenable.upperBound <= characters.count, !shortenable.isEmpty else {
            return ShortenedName(shown: text, size: floor)
        }
        let before = String(characters[..<shortenable.lowerBound])
        let name = Array(characters[shortenable])
        let after = String(characters[shortenable.upperBound...])

        func shortened(_ keep: Int, tail: String) -> String {
            let kept = String(name.prefix(keep)).trimmingTrailingWhitespace()
            return before + kept + NameFit.ellipsis + tail
        }

        if fits(shortened(0, tail: after), floor) {
            let keep = longestFit(most: name.count - 1) { fits(shortened($0, tail: after), floor) }
            return ShortenedName(shown: shortened(keep, tail: after), size: floor)
        }
        if let suffix = compactSuffix {
            let compactTail = NameFit.compactGap + suffix
            let whole = before + String(name) + compactTail
            if fits(whole, floor) { return ShortenedName(shown: whole, size: floor) }
            if fits(shortened(0, tail: compactTail), floor) {
                let keep = longestFit(most: name.count - 1) { fits(shortened($0, tail: compactTail), floor) }
                return ShortenedName(shown: shortened(keep, tail: compactTail), size: floor)
            }
        }
        return ShortenedName(shown: text, size: floor)
    }

    /// The largest count in 0...most that fits, given that 0 fits and widths grow with the count.
    static func longestFit(most: Int, fits: (Int) -> Bool) -> Int {
        var low = 0
        var high = max(0, most)
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(mid) { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

/// A group conversation's title pieces (Android `ConversationTitles`): "Priya Raman & 2 others",
/// the name's range in it, and the compact "+2".
public enum GroupTitle {
    private static let compactMax = 18
    private static let emailLocalMax = 16
    private static let emailLocalKeep = 15

    /// The short "+N" that replaces "& N others" when even "…" and the count do not fit.
    public static func compactSuffix(others: Int) -> String { "+\(others)" }

    /// The name's character range inside a composed `title`, or nil when it is not there.
    public static func nameRange(in title: String, name: String) -> Range<Int>? {
        guard !name.isEmpty, let range = title.range(of: name) else { return nil }
        let start = title.distance(from: title.startIndex, to: range.lowerBound)
        return start..<(start + name.count)
    }

    /// The short label for the first name in a group title, as the Expo app's
    /// `compactParticipantLabel`: an email keeps its local part (cut to 15 + "…" past 16
    /// characters); a long name becomes "F. Last", or is cut to 17 + "…".
    public static func compactLabel(_ raw: String) -> String {
        if raw.contains("@") {
            let local = raw.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
            let part = (local?.isEmpty == false ? local : nil) ?? raw
            return part.count > emailLocalMax ? String(part.prefix(emailLocalKeep)) + NameFit.ellipsis : part
        }
        if raw.count <= compactMax { return raw }
        let words = raw.split(whereSeparator: \.isWhitespace)
        if words.count >= 2, let initial = words.first?.first, let last = words.last {
            let abbreviated = "\(initial). \(last)"
            if abbreviated.count <= compactMax { return abbreviated }
        }
        return String(raw.prefix(compactMax - 1)) + NameFit.ellipsis
    }
}

extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }
}
