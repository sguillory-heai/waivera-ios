import Foundation
import Testing

@testable import WaiveraDesignTokens

/// Android's `WaiveraMotionSpecs` and `WaiveraSwapSpecs`, mapped to SwiftUI's spring parameters.
struct MotionTests {
    @Test func composeSpringsMapToResponseAndDampingFraction() {
        let spring = SpringSpec(stiffness: 400, dampingRatio: 0.8)
        #expect(abs(spring.response - 2 * Double.pi / 20) < 1e-9)
        #expect(spring.dampingFraction == 0.8)
        #expect(abs(spring.damping - 32) < 1e-9)
    }

    @Test(arguments: [
        (MotionSpec.fastSpatial, 1400.0, 0.9),
        (MotionSpec.defaultSpatial, 700, 0.9),
        (MotionSpec.fastEffects, 3800, 1),
        (MotionSpec.celebrate, 200, 0.8),
        (MotionSpec.pressRelease, 800, 0.6),
        (MotionSpec.pressCancel, 2400, 1),
        (MotionSpec.sendPop, 520, 0.62),
        (MotionSpec.pop, 900, 0.5),
    ])
    func springsKeepAndroidValues(spec: SpringSpec, stiffness: Double, ratio: Double) {
        #expect(spec.stiffness == stiffness)
        #expect(spec.dampingRatio == ratio)
    }

    @Test func criticallyDampedSpringsNeverOvershoot() {
        #expect(MotionSpec.fastEffects.overshoot == 0)
        #expect(MotionSpec.pressCancel.overshoot == 0)
        #expect(MotionSpec.pressRelease.overshoot > 0)
        #expect(MotionSpec.pop.overshoot > MotionSpec.pressRelease.overshoot)
    }

    @Test func tweensKeepAndroidTimings() {
        #expect(MotionSpec.exit == TweenSpec(duration: 0.060, easing: .linearOutSlowIn))
        #expect(MotionSpec.swapEnter == TweenSpec(duration: 0.150, delay: 0.040, easing: .linearOutSlowIn))
        #expect(MotionSpec.enterAfterExit == TweenSpec(duration: 0.120, delay: 0.040, easing: .fastOutSlowIn))
        #expect(MotionSpec.reducedFade == TweenSpec(duration: 0.150, easing: .linear))
        #expect(MotionSpec.skeletonPulse.duration == 0.9)
        #expect(MotionSpec.celebrateBurst.duration == 1.4)
    }

    @Test func tokensMapToSprings() {
        #expect(MotionPolicy.curve(for: .press, reduceMotion: false) == .spring(MotionSpec.fastSpatial))
        #expect(MotionPolicy.curve(for: .state, reduceMotion: false) == .spring(MotionSpec.fastEffects))
        #expect(MotionPolicy.curve(for: .layout, reduceMotion: false) == .spring(MotionSpec.defaultSpatial))
        #expect(MotionPolicy.curve(for: .navigate, reduceMotion: false) == .system)
        #expect(MotionPolicy.curve(for: .celebrate, reduceMotion: false) == .spring(MotionSpec.celebrate))
    }

    @Test func reduceMotionSnapsSpatialAndFadesEffects() {
        #expect(MotionPolicy.curve(for: .press, reduceMotion: true) == MotionCurve.none)
        #expect(MotionPolicy.curve(for: .layout, reduceMotion: true) == MotionCurve.none)
        #expect(MotionPolicy.curve(for: .state, reduceMotion: true) == .tween(MotionSpec.reducedFade))
        #expect(MotionPolicy.curve(for: .celebrate, reduceMotion: true) == .tween(MotionSpec.reducedFade))
        #expect(MotionPolicy.pop(reduceMotion: true) == MotionCurve.none)
        #expect(MotionPolicy.swapExit(reduceMotion: true) == MotionCurve.none)
        #expect(MotionPolicy.swapEnter(reduceMotion: true) == .tween(MotionSpec.reducedFade))
        #expect(!MotionPolicy.swapMoves(reduceMotion: true))
        #expect(!MotionPolicy.shakes(reduceMotion: true))
        #expect(!MotionPolicy.skeletonAnimates(reduceMotion: true))
        #expect(!MotionPolicy.celebrationBursts(reduceMotion: true))
    }

    @Test(arguments: [
        (PressDepth.row, 0.985, 0.97),
        (.card, 0.97, 0.95),
        (.button, 0.96, 0.93),
        (.compact, 0.90, 0.86),
    ])
    func pressDepths(depth: PressDepth, scale: Double, longPress: Double) {
        #expect(MotionPolicy.pressedScale(depth, reduceMotion: false) == scale)
        #expect(MotionPolicy.longPressScale(depth, reduceMotion: false) == longPress)
        #expect(MotionPolicy.pressedScale(depth, reduceMotion: true) == 1)
        #expect(MotionPolicy.longPressScale(depth, reduceMotion: true) == 1)
    }

    @Test func pressTintsOnlyRowsAndCardsWithMotionOnAndEverythingUnderReduceMotion() {
        #expect(MotionPolicy.pressedTint(.row, reduceMotion: false) == 0.06)
        #expect(MotionPolicy.pressedTint(.card, reduceMotion: false) == 0.06)
        #expect(MotionPolicy.pressedTint(.button, reduceMotion: false) == 0)
        #expect(MotionPolicy.pressedTint(.compact, reduceMotion: true) == 0.10)
        #expect(Emphasis.longPressTint == 0.16)
    }

    @Test func aQuickTapStaysVisibleForTheMinimumPress() {
        #expect(abs(MotionPolicy.releaseDelay(pressedFor: 0.02) - 0.07) < 1e-9)
        #expect(MotionPolicy.releaseDelay(pressedFor: 0.2) == 0)
        #expect(MotionPolicy.releaseDelay(pressedFor: 0, cancelled: true) == 0)
    }

    @Test func releaseBouncesUnlessAScrollTookThePress() {
        #expect(MotionPolicy.release(cancelled: false, reduceMotion: false) == .spring(MotionSpec.pressRelease))
        #expect(MotionPolicy.release(cancelled: true, reduceMotion: false) == .spring(MotionSpec.pressCancel))
    }

    @Test func longPressSinksLinearlyAfterTheArmDelay() {
        let sink = MotionPolicy.longPressSink()
        #expect(abs(sink.duration - 0.35) < 1e-9)
        #expect(sink.easing == .linear)
        #expect(MotionPolicy.longPressSink(longPressDuration: 0.1).duration == MotionTiming.longPressMinSink)
    }

    @Test func shakeStartsAndEndsAtRestAndHitsItsKeyframes() {
        #expect(ShakeKeyframes.value(at: 0) == 0)
        #expect(abs(ShakeKeyframes.value(at: 0.040) + 1) < 1e-9)
        #expect(abs(ShakeKeyframes.value(at: 0.110) - 1) < 1e-9)
        #expect(abs(ShakeKeyframes.value(at: 0.180) + 0.6) < 1e-9)
        #expect(ShakeKeyframes.value(at: 0.300) == 0)
        #expect(ShakeKeyframes.value(at: 1) == 0)
        #expect(Spacing.shakeAmplitude == 8)
        #expect(MotionTiming.rejectShakeAfterPush == 0.1)
    }

    @Test func easingEndpoints() {
        for easing in [Easing.fastOutSlowIn, .linearOutSlowIn, .linear] {
            #expect(abs(easing.value(at: 0)) < 1e-6)
            #expect(abs(easing.value(at: 1) - 1) < 1e-6)
        }
        #expect(Easing.fastOutSlowIn.value(at: 0.5) > 0.5)
        #expect(abs(Easing.linear.value(at: 0.3) - 0.3) < 1e-6)
    }

    @Test func ownSendsPopFromSmallAndOthersGlide() {
        let start = BubbleArrival.frame(progress: 0, mine: true)
        #expect(start.scale == 0.82)
        #expect(start.alpha == 0.35)
        #expect(start.offsetFraction == 1)
        #expect(BubbleArrival.frame(progress: 0, mine: false).scale == 1)
        let rest = BubbleArrival.frame(progress: 1, mine: true)
        #expect(rest.scale == 1)
        #expect(rest.alpha == 1)
        #expect(BubbleArrival.frame(progress: 3, mine: true).scale <= 1 + 0.15 * 0.18 + 1e-9)
    }

    @Test func swapAndListTimings() {
        #expect(MotionTiming.swapStartScale == 0.92)
        #expect(MotionTiming.popStartScale == 0.8)
        #expect(MotionTiming.tabPillStartScaleX == 0.55)
        #expect(MotionTiming.swapSlideDivisor == 3)
        #expect(MotionTiming.swapRollDivisor == 2)
        #expect(MotionTiming.listSettle == 0.25)
        #expect(MotionTiming.syncedBeat == 0.9)
        #expect(MotionTiming.focusCloseWait == 0.6)
    }
}
