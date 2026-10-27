/// When a skeleton is on screen. Fast loads never flash one; slow loads show it within ~300ms and
/// keep it at least ~300ms so it does not blink (10-design-feedback §3, AGENTS.md).
public struct SkeletonTiming: Equatable, Sendable {
    public static let standard = SkeletonTiming(showDelay: 0.3, minimumVisible: 0.3)

    public let showDelay: Double
    public let minimumVisible: Double

    public init(showDelay: Double, minimumVisible: Double) {
        self.showDelay = showDelay
        self.minimumVisible = minimumVisible
    }

    /// Whether the skeleton should be visible `elapsed` seconds after loading started.
    /// `finishedAt` is when loading ended (seconds after start), or `nil` while still loading.
    public func isVisible(elapsed: Double, finishedAt: Double?) -> Bool {
        guard let finishedAt else { return elapsed >= showDelay }
        guard finishedAt >= showDelay else { return false }
        return elapsed >= showDelay && elapsed < finishedAt.clampedMinimum(showDelay + minimumVisible)
    }

    /// How long content must wait after loading finished, so the skeleton meets its minimum.
    public func contentDelay(finishedAt: Double) -> Double {
        guard finishedAt >= showDelay else { return 0 }
        return max(0, showDelay + minimumVisible - finishedAt)
    }
}

private extension Double {
    func clampedMinimum(_ minimum: Double) -> Double { Swift.max(self, minimum) }
}
