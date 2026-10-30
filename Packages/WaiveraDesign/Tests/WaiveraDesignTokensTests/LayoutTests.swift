import Testing

@testable import WaiveraDesignTokens

struct LayoutTests {
    @Test func hitTargetIsAppleMinimum() {
        #expect(ControlSize.minHitTarget == 44)
        #expect(ControlSize.buttonHeight == 48)
        #expect(ControlSize.ctaHeight == 56)
    }

    @Test func avatarsAreSoftRoundedSquares() {
        #expect(AvatarGeometry.cornerRadius(size: 44) == 11)
        #expect(AvatarGeometry.cornerRadius(size: 24) == 8)
        #expect(AvatarGeometry.cornerRadius(size: 96) == 23)
        #expect(AvatarGeometry.fallbackGlyphSize(size: 44) == 22)
    }

    @Test(arguments: [
        ("Alex Rivera", "AR"),
        ("priya", "P"),
        ("Jordan  van Lee", "JL"),
        ("R. Okonkwo", "RO"),
        ("", ""),
        ("   ", ""),
        ("Émile Zola", "ÉZ"),
        ("— Sam", "S"),
    ])
    func initials(name: String, expected: String) {
        #expect(AvatarGeometry.initials(for: name) == expected)
    }

    @Test func badgeCapsAtNinetyNine() {
        #expect(BadgeFormatter.text(for: 0) == nil)
        #expect(BadgeFormatter.text(for: -3) == nil)
        #expect(BadgeFormatter.text(for: 7) == "7")
        #expect(BadgeFormatter.text(for: 100) == "99+")
    }

    @Test func elevationReadsAsAShadowFromAbove() {
        let glow = Elevation.shadow(for: Elevation.buttonGlow)
        #expect(glow.radius == 6)
        #expect(glow.y == 3)
    }
}

/// v7 item 1: the leading tile centres on a standard row and pins near the top on a tall one.
struct LeadingTileTests {
    // Body text at the default size: a 22pt title line, 2pt gap, 18pt subtitle line.
    let standard = LeadingTileAlignment.twoLineRowContentHeight(titleLine: 22, gap: 2, subtitleLine: 18)

    @Test func standardHeightAllowsHalfALineOfSlack() {
        #expect(standard == 51)
    }

    @Test func aTwoLineRowCentresTheTile() {
        #expect(LeadingTileAlignment.offset(tileHeight: 40, contentHeight: 42, standardHeight: standard) == 1)
        #expect(!LeadingTileAlignment.isPinned(contentHeight: 42, standardHeight: standard))
        #expect(!LeadingTileAlignment.isPinned(contentHeight: 51, standardHeight: standard))
    }

    @Test func aThirdLinePinsTheTileToTheTitle() {
        let tall = 22.0 + 2 + 18 * 2
        #expect(LeadingTileAlignment.isPinned(contentHeight: tall, standardHeight: standard))
        #expect(LeadingTileAlignment.offset(tileHeight: 40, contentHeight: tall, standardHeight: standard) == 2)
    }

    @Test func aPinnedTileNeverSitsLowerThanCentred() {
        // A tall tile in a barely tall row: centring already puts it above the pin.
        #expect(LeadingTileAlignment.offset(tileHeight: 56, contentHeight: 54, standardHeight: standard) == -1)
    }

    @Test func largeTextRaisesTheThreshold() {
        let large = LeadingTileAlignment.twoLineRowContentHeight(titleLine: 34, gap: 2, subtitleLine: 28)
        #expect(!LeadingTileAlignment.isPinned(contentHeight: 34 + 2 + 28, standardHeight: large))
        #expect(LeadingTileAlignment.isPinned(contentHeight: 34 + 2 + 56, standardHeight: large))
    }
}

struct SegmentAndBannerTests {
    @Test func segmentsShareEquallyWhileTheWidestFits() {
        #expect(SegmentFit.fit(segmentWidths: [60, 80, 70], available: 300) == .equal)
    }

    @Test func segmentsGoProportionalThenScroll() {
        #expect(SegmentFit.fit(segmentWidths: [60, 160, 70], available: 300) == .proportional([60, 160, 70]))
        #expect(SegmentFit.fit(segmentWidths: [160, 160, 70], available: 300) == .scroll)
    }

    @Test func bannerActionStacksAtLargeTextOrWhenWide() {
        #expect(!BannerLayoutRule.actionStacks(category: .large, actionWidth: 60, availableWidth: 300))
        #expect(BannerLayoutRule.actionStacks(category: .xxxLarge, actionWidth: 60, availableWidth: 300))
        #expect(BannerLayoutRule.actionStacks(category: .large, actionWidth: 120, availableWidth: 300))
        #expect(
            BannerLayoutRule.actionStacks(category: .large, actionWidth: 60, availableWidth: 300, messageLinesBeside: 3)
        )
    }
}

struct TypographyTests {
    @Test func largeMeansAbove130PercentAndExtraLargeFrom150() {
        #expect(!TypeScale.isLarge(.xxLarge))
        #expect(TypeScale.isLarge(.xxxLarge))
        #expect(!TypeScale.isExtraLarge(.xxxLarge))
        #expect(TypeScale.isExtraLarge(.accessibility1))
        #expect(TypeScale.isExtraLarge(.accessibility5))
    }

    @Test func ringCountStopsGrowingAt130Percent() {
        #expect(RingMath.maximumCategory(compact: false) == .xxLarge)
        #expect(RingMath.maximumCategory(compact: true) == .large)
    }

    @Test func styleSpecsKeepAndroidValues() {
        #expect(TextStyleToken.bodyMedium.spec == .init(size: 15, lineHeight: 22, weight: .regular, trackingEm: 0))
        #expect(TextStyleToken.headlineSmall.spec.weight == .extraBold)
        #expect(TextStyleToken.labelLarge.spec.size == 16)
        #expect(abs(TextStyleToken.eyebrow.spec.tracking - 1.05) < 1e-9)
    }

    @Test func everyStyleHasASpecAndADynamicTypeBase() {
        for style in TextStyleToken.allCases {
            #expect(style.spec.size > 0)
            #expect(style.spec.lineHeight >= style.spec.size, "\(style)")
        }
        #expect(TextStyleBase.closest(to: 17) == .body)
        #expect(TextStyleBase.closest(to: 11) == .caption2)
    }

    @Test func legacyRolesMapToAndroidStyles() {
        #expect(LegacyFontRole.screenTitle.style == .headlineSmall)
        #expect(LegacyFontRole.body.style == .bodyMedium)
        #expect(LegacyFontRole.button.style == .labelLarge)
    }

    @Test func fontsArePlusJakartaSans() {
        #expect(FontWeightToken.extraBold.postScriptName == "PlusJakartaSans-ExtraBold")
        #expect(FontWeightToken.allCases.count == 5)
    }

    @Test func nameLinesGrowAtLargeText() {
        #expect(NameLines.listRow(.large) == 1)
        #expect(NameLines.listRow(.accessibility2) == 2)
        #expect(NameLines.hero(.large) == 2)
        #expect(NameLines.hero(.xxxLarge) == 3)
        #expect(NameLines.greeting == 2)
    }
}
