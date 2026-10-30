import Testing

@testable import WaiveraDesignTokens

/// The palette is Android's built values (`WaiveraPalette.kt`, brand-rollout 554e7d1).
struct ColorTokenTests {
    @Test func brandVioletIsTheApprovedAndroidValue() {
        #expect(ColorToken.accent.light == RGBColor(hex: 0x6A3DC4))
        #expect(ColorToken.accent.dark == RGBColor(hex: 0xB79CFF))
        #expect(ColorToken.accentFill.dark == RGBColor(hex: 0x8048E6))
        #expect(ColorToken.link.dark == RGBColor(hex: 0xC3ABFF))
    }

    @Test func plumDarkSurfacesStepUpByLightness() {
        let background = ColorToken.background.dark.relativeLuminance
        let surface = ColorToken.surface.dark.relativeLuminance
        let raised = ColorToken.raised.dark.relativeLuminance
        #expect(background < surface)
        #expect(surface < raised)
    }

    @Test(arguments: [false, true])
    func textMeetsBodyContrastOnEverySurface(isDark: Bool) {
        for background in [ColorToken.background, .surface, .surfaceMuted, .raised] {
            let ratio = ColorToken.text.value(isDark: isDark).contrastRatio(against: background.value(isDark: isDark))
            #expect(ratio >= 4.5, "text on \(background) dark=\(isDark) is \(ratio)")
            let secondary = ColorToken.textSecondary.value(isDark: isDark)
                .contrastRatio(against: background.value(isDark: isDark))
            #expect(secondary >= 4.5, "secondary on \(background) dark=\(isDark) is \(secondary)")
        }
    }

    @Test(arguments: [false, true])
    func tertiaryTextStaysReadableAsMetadata(isDark: Bool) {
        let ratio = ColorToken.textTertiary.value(isDark: isDark)
            .contrastRatio(against: ColorToken.surface.value(isDark: isDark))
        #expect(ratio >= 3)
    }

    /// Buttons carry the white sheen, so their labels must pass over its brightest band too.
    @Test(arguments: [false, true])
    func buttonLabelsMeetContrastUnderTheSheen(isDark: Bool) {
        let fills: [(ColorToken, ColorToken)] = [
            (.accentFill, .onAccent), (.selectedFill, .onSelectedFill), (.dangerFill, .onDangerFill),
        ]
        let sheen = ColorToken.buttonSheen.value(isDark: isDark)
        for (fill, ink) in fills {
            let base = fill.value(isDark: isDark)
            for background in [base, sheen.composited(over: base)] {
                let ratio = ink.value(isDark: isDark).contrastRatio(against: background)
                #expect(ratio >= 4.5, "\(ink) on \(fill) dark=\(isDark) is \(ratio)")
            }
        }
    }

    /// Count badges are flat (no sheen): white on the attention rose, 5.7:1 light and 4.6:1 dark.
    @Test(arguments: [false, true])
    func attentionCountsMeetContrast(isDark: Bool) {
        for fill in [ColorToken.unread, .navBadge] {
            let ratio = ColorToken.onAccent.value(isDark: isDark).contrastRatio(against: fill.value(isDark: isDark))
            #expect(ratio >= 4.5, "\(fill) dark=\(isDark) is \(ratio)")
        }
    }

    @Test(arguments: [false, true])
    func linksMeetContrast(isDark: Bool) {
        let ratio = ColorToken.link.value(isDark: isDark).contrastRatio(
            against: ColorToken.surface.value(isDark: isDark)
        )
        #expect(ratio >= 4.5)
    }

    @Test(arguments: TileTone.allCases)
    func tileGlyphsMeetContrastOnTheirTile(tone: TileTone) {
        for isDark in [false, true] {
            let ratio = tone.content(isDark: isDark).contrastRatio(against: tone.container(isDark: isDark))
            #expect(ratio >= 4.5, "\(tone) dark=\(isDark) is \(ratio)")
        }
    }

    @Test(arguments: [false, true])
    func skeletonsAndAvatarsAreVisibleOnTheirSurfaces(isDark: Bool) {
        let surface = ColorToken.surface.value(isDark: isDark)
        #expect(ColorToken.skeletonBase.value(isDark: isDark).contrastRatio(against: surface) >= 1.3)
        #expect(ColorToken.avatarFill.value(isDark: isDark).contrastRatio(against: surface) >= 1.3)
    }

    @Test func countTonesSeparateAttentionFromTotals() {
        #expect(CountTone.attention.fill == .unread)
        #expect(CountTone.info.fill == .chipNeutral)
        for isDark in [false, true] {
            let info = CountTone.info.ink.value(isDark: isDark)
                .contrastRatio(against: CountTone.info.fill.value(isDark: isDark))
            #expect(info >= 4.5)
        }
    }

    @Test func focusScrimIsDarkerThanTheSheetScrim() {
        #expect(ColorToken.focusScrim.light.alpha == 0.70)
        #expect(ColorToken.focusScrim.dark.alpha == 0.76)
        #expect(ColorToken.scrim.light.alpha == 0.36)
    }

    @Test func derivedAccentTokensAreTranslucentAccent() {
        #expect(ColorToken.accentWash.light == RGBColor(hex: 0x6A3DC4, alpha: 0.08))
        #expect(ColorToken.accentBorder.dark.alpha == 0.16)
    }

    @Test func everyRoleHasAValueInBothThemes() {
        for token in ColorToken.allCases {
            #expect(token.light.alpha > 0, "\(token) light")
            #expect(token.dark.alpha > 0, "\(token) dark")
        }
    }

    @Test func logoGradientMatchesTheDrawable() {
        #expect(LogoGradient.stops.map(\.location) == [0.245234, 0.567368, 1])
        #expect(LogoGradient.stops.first?.color == RGBColor(hex: BrandPalette.brandViolet))
    }

    @Test func compositingAndInterpolation() {
        let half = RGBColor(hex: 0x000000, alpha: 0.5).composited(over: RGBColor(hex: 0xFFFFFF))
        #expect(abs(half.red - 0.5) < 0.0001)
        #expect(half.alpha == 1)
        let mid = RGBColor(hex: 0x000000).interpolated(to: RGBColor(hex: 0xFFFFFF), fraction: 0.25)
        #expect(abs(mid.green - 0.25) < 0.0001)
        let ratio = RGBColor(hex: 0x000000).contrastRatio(against: RGBColor(hex: 0xFFFFFF))
        #expect(abs(ratio - 21) < 0.001)
    }
}
