import Foundation
import Testing

@testable import ChatFeature

@Suite("Image preview swipe to close")
struct ImageDismissTests {
    @Test func aDragPastTheDistanceCloses() {
        #expect(ImageDismiss.shouldClose(offset: 121, velocity: 0))
        #expect(ImageDismiss.shouldClose(offset: -121, velocity: 0))
        #expect(!ImageDismiss.shouldClose(offset: 80, velocity: 0))
    }

    @Test func aFlingClosesUnlessItIsBackTowardRest() {
        #expect(ImageDismiss.shouldClose(offset: 20, velocity: 1_200))
        #expect(ImageDismiss.shouldClose(offset: -20, velocity: -1_200))
        #expect(!ImageDismiss.shouldClose(offset: 200, velocity: -1_200))
    }

    @Test func theBackdropFadesInProportionAndStopsAtTheFadeDistance() {
        #expect(ImageDismiss.progress(offset: 0) == 0)
        #expect(ImageDismiss.progress(offset: -160) == 0.5)
        #expect(ImageDismiss.progress(offset: 900) == 1)
        #expect(ImageDismiss.progress(offset: 50, fadeDistance: 0) == 0)
    }
}
