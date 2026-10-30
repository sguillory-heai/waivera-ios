import Testing

@testable import WaiveraDesignTokens

/// v7 items 3 and 4: one-line names shrink at most 15%, then only the name is cut.
struct NameFitTests {
    /// A monospaced stand-in for text measurement: each character is `size * 0.5` wide.
    private func fits(width: Double) -> (String, Double) -> Bool {
        { text, size in Double(text.count) * size * 0.5 <= width }
    }

    @Test func sizesStepDownToEightyFivePercent() {
        let sizes = NameFit.sizes(full: 16)
        #expect(sizes.first == 16)
        #expect(abs((sizes.last ?? 0) - 13.6) < 1e-9)
        #expect(sizes == sizes.sorted(by: >))
    }

    @Test func aTitleThatFitsKeepsItsFullSize() {
        let fit = ShortenedNameFitter.fit(
            text: "Priya & 2 others",
            shortenable: 0..<5,
            fullSize: 16,
            fits: fits(width: 200)
        )
        #expect(fit == ShortenedName(shown: "Priya & 2 others", size: 16))
    }

    @Test func aSlightlyLongTitleShrinksBeforeCutting() {
        // 16 characters: 128pt at 16, 108.8pt at the floor.
        let fit = ShortenedNameFitter.fit(
            text: "Priya & 2 others",
            shortenable: 0..<5,
            fullSize: 16,
            fits: fits(width: 120)
        )
        #expect(fit.shown == "Priya & 2 others")
        #expect(fit.size < 16)
        #expect(fit.size >= 13.6)
    }

    @Test func onlyTheNameIsCutSoTheCountAlwaysShows() {
        let title = "Maria-Fernanda Rodriguez & 4 others"
        let range = GroupTitle.nameRange(in: title, name: "Maria-Fernanda Rodriguez")
        #expect(range == 0..<24)
        let fit = ShortenedNameFitter.fit(
            text: title,
            shortenable: range ?? 0..<0,
            fullSize: 16,
            compactSuffix: "+4",
            fits: fits(width: 150)
        )
        #expect(abs(fit.size - 13.6) < 1e-9)
        #expect(fit.shown == "Maria-Fern… & 4 others")
    }

    @Test func theCompactSuffixTakesOverWhenTheCountCannotFit() {
        let title = "Maria-Fernanda Rodriguez & 4 others"
        let fit = ShortenedNameFitter.fit(
            text: title,
            shortenable: 0..<24,
            fullSize: 16,
            compactSuffix: "+4",
            fits: fits(width: 80)
        )
        #expect(fit.shown == "Maria-F…\u{00A0}+4")
    }

    @Test func nothingFitsLeavesTheWholeTitleForTailTruncation() {
        let fit = ShortenedNameFitter.fit(
            text: "Maria & 4 others",
            shortenable: 0..<5,
            fullSize: 16,
            fits: fits(width: 10)
        )
        #expect(fit.shown == "Maria & 4 others")
        #expect(abs(fit.size - 13.6) < 1e-9)
    }

    @Test func cutNamesDropTrailingSpaces() {
        let fit = ShortenedNameFitter.fit(
            text: "Ana Maria Lopez & 2 others",
            shortenable: 0..<15,
            fullSize: 10,
            fits: fits(width: 69)
        )
        #expect(fit.shown == "Ana… & 2 others")
    }

    @Test(arguments: [
        ("Priya Raman", "Priya Raman"),
        ("Maria-Fernanda Rodriguez", "M. Rodriguez"),
        ("Bartholomew Montgomery-Fairweather", "Bartholomew Montg…"),
        ("someone.with.a.long@example.com", "someone.with.a.…"),
        ("short@example.com", "short"),
    ])
    func compactLabel(raw: String, expected: String) {
        #expect(GroupTitle.compactLabel(raw) == expected)
    }

    @Test func compactSuffix() {
        #expect(GroupTitle.compactSuffix(others: 12) == "+12")
        #expect(GroupTitle.nameRange(in: "A & 1 other", name: "Zed") == nil)
    }
}
