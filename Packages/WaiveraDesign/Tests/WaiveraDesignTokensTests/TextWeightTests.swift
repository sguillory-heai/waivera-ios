import Testing

@testable import WaiveraDesignTokens

/// A style drawn in another face keeps its size, line height and tracking (chat list unread names).
struct TextWeightTests {
    @Test func aWeightOverrideChangesOnlyTheFace() {
        let spec = TextStyleToken.titleSmall.spec
        let heavy = spec.weighted(.extraBold)
        #expect(heavy.weight == .extraBold)
        #expect(heavy.size == spec.size)
        #expect(heavy.lineHeight == spec.lineHeight)
        #expect(heavy.trackingEm == spec.trackingEm)
        #expect(heavy.weighted(.semibold).weight == .semibold)
    }

    @Test func noOverrideKeepsTheStyle() {
        let spec = TextStyleToken.bodySmall.spec
        #expect(spec.weighted(nil) == spec)
    }
}
