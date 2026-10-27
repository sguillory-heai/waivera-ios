/// Exponential backoff with jitter for hub reconnects. Retries never stop while
/// the app is in the foreground; the delay is capped so a worker coming back into
/// signal reconnects within `maxDelay`. Same numbers as the Android policy.
public struct ReconnectPolicy: Sendable {
    public static let defaultBaseDelay: Duration = .milliseconds(500)
    public static let defaultMaxDelay: Duration = .seconds(30)

    // Keeps the shift well inside Int64 range; the cap applies long before this.
    private static let maxShift = 20

    private let baseMilliseconds: Int64
    private let maxMilliseconds: Int64

    public init(baseDelay: Duration = defaultBaseDelay, maxDelay: Duration = defaultMaxDelay) {
        baseMilliseconds = max(1, Self.milliseconds(baseDelay))
        maxMilliseconds = max(baseMilliseconds, Self.milliseconds(maxDelay))
    }

    /// Delay before reconnect `attempt`, counted from 1. The first retry is immediate.
    public func delay(forAttempt attempt: Int) -> Duration {
        var generator = SystemRandomNumberGenerator()
        return delay(forAttempt: attempt, using: &generator)
    }

    public func delay(forAttempt attempt: Int, using generator: inout some RandomNumberGenerator) -> Duration {
        guard attempt > 1 else { return .zero }
        let shift = min(attempt - 2, Self.maxShift)
        let ceiling = min(maxMilliseconds, baseMilliseconds << shift)
        return .milliseconds(Int64.random(in: (ceiling / 2)...ceiling, using: &generator))
    }

    private static func milliseconds(_ duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
    }
}
