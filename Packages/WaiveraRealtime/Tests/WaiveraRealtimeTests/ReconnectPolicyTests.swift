import Testing
@testable import WaiveraRealtime

struct ReconnectPolicyTests {
    @Test func firstRetryIsImmediate() {
        var generator = SeededGenerator(seed: 1)
        #expect(ReconnectPolicy().delay(forAttempt: 1, using: &generator) == .zero)
    }

    @Test(arguments: [(2, 250, 500), (3, 500, 1_000), (4, 1_000, 2_000), (8, 15_000, 30_000)])
    func delayGrowsWithinJitterBounds(attempt: Int, lower: Int, upper: Int) {
        var generator = SeededGenerator(seed: UInt64(attempt))
        let policy = ReconnectPolicy()
        for _ in 0..<200 {
            let delay = policy.delay(forAttempt: attempt, using: &generator)
            #expect(delay >= .milliseconds(lower) && delay <= .milliseconds(upper))
        }
    }

    @Test func delayIsCappedForVeryLongOutages() {
        var generator = SeededGenerator(seed: 7)
        let delay = ReconnectPolicy().delay(forAttempt: 10_000, using: &generator)
        #expect(delay <= ReconnectPolicy.defaultMaxDelay)
        #expect(delay >= .seconds(15))
    }
}

/// SplitMix64, so jitter is repeatable in tests.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
