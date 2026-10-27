import Testing

@testable import WaiveraDesignTokens

struct HapticsTests {
    @Test func mapFollowsTheFeedbackMap() {
        #expect(HapticMap.pattern(for: .toggle) == .selection)
        #expect(HapticMap.pattern(for: .selection) == .selection)
        #expect(HapticMap.pattern(for: .swipeThreshold) == .impactLight)
        #expect(HapticMap.pattern(for: .success) == .success)
        #expect(HapticMap.pattern(for: .failure) == .error)
        #expect(HapticMap.pattern(for: .warning) == .warning)
        #expect(HapticMap.pattern(for: .longPress) == .impactMedium)
        #expect(HapticMap.pattern(for: .messageSent) == .impactLight)
    }

    @Test func incomingMessagesNeverBuzz() {
        #expect(HapticMap.pattern(for: .messageReceivedWhileVisible) == nil)
    }

    @Test func settingsSwitchSilencesEverything() {
        var gate = HapticGate(isEnabled: false)
        for (index, event) in HapticEvent.allCases.enumerated() {
            #expect(gate.pattern(for: event, now: Double(index)) == nil)
        }
    }

    @Test func burstOfSendsPlaysOnce() {
        var gate = HapticGate()
        #expect(gate.pattern(for: .messageSent, now: 0) == .impactLight)
        #expect(gate.pattern(for: .messageSent, now: 0.1) == nil)
        #expect(gate.pattern(for: .messageSent, now: 0.2) == nil)
        #expect(gate.pattern(for: .messageSent, now: 0.5) == .impactLight)
    }

    @Test func differentPatternsDoNotThrottleEachOther() {
        var gate = HapticGate()
        #expect(gate.pattern(for: .messageSent, now: 0) == .impactLight)
        #expect(gate.pattern(for: .failure, now: 0.05) == .error)
    }
}
