import Testing

@testable import WaiveraDesignTokens

struct ColorTokenTests {
    @Test func brandAccentMatchesAgentsMD() {
        #expect(ColorToken.accent.light == RGBColor(hex: 0x7E57C2))
        #expect(ColorToken.accent.dark == RGBColor(hex: 0xA78BFA))
    }

    @Test func mutedSurfaceRecedesInDarkAndAdvancesInLight() {
        let surface = ColorToken.surface
        let muted = ColorToken.surfaceMuted
        #expect(muted.dark.relativeLuminance < surface.dark.relativeLuminance)
        #expect(muted.light.relativeLuminance < surface.light.relativeLuminance)
    }

    @Test(arguments: [false, true])
    func textMeetsBodyContrastOnEverySurface(isDark: Bool) {
        for background in [ColorToken.background, .surface, .surfaceMuted] {
            let ratio = ColorToken.text.value(isDark: isDark).contrastRatio(against: background.value(isDark: isDark))
            #expect(ratio >= 4.5, "text on \(background) dark=\(isDark) is \(ratio)")
        }
    }

    @Test(arguments: [false, true])
    func secondaryTextMeetsContrastOnSurface(isDark: Bool) {
        let ratio = ColorToken.textSecondary.value(isDark: isDark)
            .contrastRatio(against: ColorToken.surface.value(isDark: isDark))
        #expect(ratio >= 4.5)
    }

    @Test(arguments: [false, true])
    func filledButtonLabelsMeetContrast(isDark: Bool) {
        let accent = ColorToken.onAccent.value(isDark: isDark).contrastRatio(
            against: ColorToken.accent.value(isDark: isDark)
        )
        let danger = ColorToken.onDanger.value(isDark: isDark).contrastRatio(
            against: ColorToken.danger.value(isDark: isDark)
        )
        #expect(accent >= 4.5, "accent label \(accent)")
        #expect(danger >= 4.5, "danger label \(danger)")
    }

    @Test func derivedAccentTokensAreTranslucentAccent() {
        #expect(ColorToken.accentWash.light == RGBColor(hex: 0x7E57C2, alpha: 0.08))
        #expect(ColorToken.accentBorder.dark.alpha == 0.16)
        #expect(ColorToken.scrim.light.alpha == 0.36)
    }

    @Test func contrastOfBlackOnWhiteIsTwentyOne() {
        let ratio = RGBColor(hex: 0x000000).contrastRatio(against: RGBColor(hex: 0xFFFFFF))
        #expect(abs(ratio - 21) < 0.001)
    }
}
