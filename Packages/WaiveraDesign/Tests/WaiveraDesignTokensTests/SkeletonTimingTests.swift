import Testing

@testable import WaiveraDesignTokens

struct SkeletonTimingTests {
    let timing = SkeletonTiming.standard

    @Test func fastLoadNeverShowsASkeleton() {
        #expect(!timing.isVisible(elapsed: 0.05, finishedAt: nil))
        #expect(!timing.isVisible(elapsed: 0.2, finishedAt: 0.1))
        #expect(timing.contentDelay(finishedAt: 0.1) == 0)
    }

    @Test func slowLoadShowsWithinThreeHundredMilliseconds() {
        #expect(!timing.isVisible(elapsed: 0.29, finishedAt: nil))
        #expect(timing.isVisible(elapsed: 0.3, finishedAt: nil))
        #expect(timing.isVisible(elapsed: 1.5, finishedAt: nil))
    }

    @Test func skeletonStaysAtLeastItsMinimum() {
        // Load finished just after the skeleton appeared: hold it until 0.6s.
        #expect(timing.isVisible(elapsed: 0.45, finishedAt: 0.35))
        #expect(!timing.isVisible(elapsed: 0.6, finishedAt: 0.35))
        #expect(abs(timing.contentDelay(finishedAt: 0.35) - 0.25) < 0.000_1)
    }

    @Test func longLoadHidesAsSoonAsItFinishes() {
        #expect(!timing.isVisible(elapsed: 2.01, finishedAt: 2))
        #expect(timing.contentDelay(finishedAt: 2) == 0)
    }
}

struct SkeletonRemainingTests {
    @Test func remainingVisibleNeverNegative() {
        #expect(abs(SkeletonTiming.standard.remainingVisible(shownFor: 0.1) - 0.2) < 0.000_1)
        #expect(SkeletonTiming.standard.remainingVisible(shownFor: 5) == 0)
    }
}
