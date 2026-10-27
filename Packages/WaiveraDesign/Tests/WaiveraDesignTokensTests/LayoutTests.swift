import Testing

@testable import WaiveraDesignTokens

struct LayoutTests {
    @Test func hitTargetIsAppleMinimum() {
        #expect(ControlSize.minHitTarget == 44)
        #expect(ControlSize.buttonHeight >= ControlSize.minHitTarget)
    }

    @Test func avatarRadiusFollowsTheExpoRule() {
        #expect(AvatarGeometry.cornerRadius(size: 44, rounded: false) == 11)
        #expect(AvatarGeometry.cornerRadius(size: 24, rounded: false) == 8)
        #expect(AvatarGeometry.cornerRadius(size: 44, rounded: true) == 22)
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
    ])
    func initials(name: String, expected: String) {
        #expect(AvatarGeometry.initials(for: name) == expected)
    }

    @Test func badgeCapsAtNinetyNine() {
        #expect(BadgeFormatter.text(for: 0) == nil)
        #expect(BadgeFormatter.text(for: -3) == nil)
        #expect(BadgeFormatter.text(for: 7) == "7")
        #expect(BadgeFormatter.text(for: 99) == "99")
        #expect(BadgeFormatter.text(for: 100) == "99+")
    }
}
