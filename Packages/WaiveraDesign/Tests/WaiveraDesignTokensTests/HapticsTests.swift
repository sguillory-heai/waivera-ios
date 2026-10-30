import Testing

@testable import WaiveraDesignTokens

/// The owner's policy (2026-10-29): only a failed send and a wrong sign-in vibrate.
struct HapticsTests {
    @Test func onlyTwoMomentsExist() {
        #expect(Set(HapticMoment.allCases) == [.sendFailed, .signInRejected])
    }

    @Test func bothPlayTheErrorSignal() {
        for moment in HapticMoment.allCases {
            #expect(HapticMap.pattern(for: moment) == .error)
        }
    }

    @Test func settingsSwitchSilencesEverything() {
        var gate = HapticGate(isEnabled: false)
        for (index, moment) in HapticMoment.allCases.enumerated() {
            #expect(gate.pattern(for: moment, now: Double(index)) == nil)
        }
    }

    @Test func aBurstOfFailuresPlaysOnce() {
        var gate = HapticGate()
        #expect(gate.pattern(for: .sendFailed, now: 0) == .error)
        #expect(gate.pattern(for: .sendFailed, now: 0.1) == nil)
        #expect(gate.pattern(for: .sendFailed, now: 0.149) == nil)
        #expect(gate.pattern(for: .sendFailed, now: 0.4) == .error)
    }

    @Test func differentMomentsDoNotThrottleEachOther() {
        var gate = HapticGate()
        #expect(gate.pattern(for: .sendFailed, now: 0) == .error)
        #expect(gate.pattern(for: .signInRejected, now: 0.05) == .error)
    }
}
