import Foundation
import Testing

@testable import WaiveraDesignTokens

@Suite("Avatar tiles")
struct AvatarTilesTests {
    /// Values from Android's `AvatarTiles.pairFor` (Kotlin `String.hashCode` floor-mod 6), so a
    /// person wears the same colours on both platforms.
    @Test func matchesAndroidsPick() {
        #expect(AvatarTiles.index(for: "") == 0)
        #expect(AvatarTiles.index(for: "a") == 97 % 6)
        #expect(AvatarTiles.index(for: "ab") == (97 * 31 + 98) % 6)
    }

    @Test func caseAndOuterSpacesDoNotMatter() {
        #expect(AvatarTiles.index(for: "  Priya Raman ") == AvatarTiles.index(for: "priya raman"))
    }

    /// Long names overflow 32 bits; the pick wraps like Kotlin and stays in range.
    @Test func longNamesWrapAndStayInRange() {
        let name = String(repeating: "Alexandria Montgomery-Featherstonehaugh ", count: 8)
        var hash: Int32 = 0
        for unit in name.trimmingCharacters(in: .whitespaces).lowercased().utf16 { hash = hash &* 31 &+ Int32(unit) }
        let expected = Int(((hash % 6) + 6) % 6)
        #expect(AvatarTiles.index(for: name) == expected)
        #expect((0..<AvatarTiles.pairs.count).contains(AvatarTiles.index(for: name)))
    }

    @Test func sixPairs() {
        #expect(AvatarTiles.pairs.count == 6)
        #expect(AvatarTiles.pairs[0].start == RGBColor(hex: 0x7E57C2))
    }
}
