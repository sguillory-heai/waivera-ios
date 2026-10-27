import Testing

@testable import WaiveraDesignTokens

struct MotionTests {
    @Test func tokensMatchTheUXResearchTable() {
        #expect(MotionPolicy.curve(for: .press, reduceMotion: false) == .snappy(duration: 0.2))
        #expect(MotionPolicy.curve(for: .state, reduceMotion: false) == .smooth(duration: 0.25))
        #expect(MotionPolicy.curve(for: .layout, reduceMotion: false) == .smooth(duration: 0.35))
        #expect(MotionPolicy.curve(for: .navigate, reduceMotion: false) == .system)
        #expect(MotionPolicy.curve(for: .celebrate, reduceMotion: false) == .bouncy(duration: 0.4, extraBounce: 0.1))
    }

    @Test func reduceMotionSwapsToTheReducedToken() {
        #expect(MotionPolicy.curve(for: .press, reduceMotion: true) == MotionCurve.none)
        for token in [MotionToken.state, .layout, .celebrate] {
            #expect(MotionPolicy.curve(for: token, reduceMotion: true) == .crossFade(duration: 0.15))
        }
        #expect(MotionPolicy.curve(for: .navigate, reduceMotion: true) == .system)
    }

    @Test func pressScaleIsDisabledUnderReduceMotion() {
        #expect(MotionPolicy.pressedScale(reduceMotion: false) == 0.96)
        #expect(MotionPolicy.pressedScale(reduceMotion: true) == 1)
    }

    @Test func skeletonIsStaticUnderReduceMotion() {
        #expect(MotionPolicy.skeletonAnimates(reduceMotion: false))
        #expect(!MotionPolicy.skeletonAnimates(reduceMotion: true))
    }
}
