import Foundation

/// Swipe down (or up) to close the image preview (Android `ImageDismiss`). Letting go farther
/// than `distance` from rest, or flicking faster than `flingVelocity` the way the image is going,
/// closes it; anything less springs it back. The backdrop fades in proportion to the drag and is
/// fully faded at `fadeDistance`.
enum ImageDismiss {
    static let distance: CGFloat = 120
    static let flingVelocity: CGFloat = 1_000
    static let fadeDistance: CGFloat = 320
    /// Far enough to carry the image off any screen before the preview closes.
    static let offScreen: CGFloat = 1_200

    /// How far through the backdrop's fade a drag of `offset` is, 0 at rest to 1.
    static func progress(offset: CGFloat, fadeDistance: CGFloat = fadeDistance) -> CGFloat {
        guard fadeDistance > 0 else { return 0 }
        return min(max(abs(offset) / fadeDistance, 0), 1)
    }

    /// Whether letting go at `offset` with `velocity` points per second closes the preview. A
    /// fast flick back toward rest keeps it open even past the distance: the finger changed its mind.
    static func shouldClose(
        offset: CGFloat,
        velocity: CGFloat,
        distance: CGFloat = distance,
        flingVelocity: CGFloat = flingVelocity
    ) -> Bool {
        let fast = abs(velocity) >= flingVelocity
        let towardRest = offset != 0 && velocity != 0 && (velocity > 0) != (offset > 0)
        if fast { return !towardRest }
        return abs(offset) >= distance
    }
}
