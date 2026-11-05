#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Splits the row's width between its children by weight (Compose `Modifier.weight`), so a
    /// wider button can never squeeze its neighbour's label away.
    struct WeightedRow: Layout {
        var weights: [CGFloat]
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
            let widths = columnWidths(for: proposal.width, count: subviews.count)
            var height: CGFloat = 0
            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(ProposedViewSize(width: widths[index], height: proposal.height))
                height = max(height, size.height)
            }
            let total = proposal.width ?? widths.reduce(spacing * CGFloat(max(subviews.count - 1, 0)), +)
            return CGSize(width: total, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
            let widths = columnWidths(for: bounds.width, count: subviews.count)
            var x = bounds.minX
            for (index, subview) in subviews.enumerated() {
                subview.place(
                    at: CGPoint(x: x, y: bounds.midY),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: widths[index], height: bounds.height)
                )
                x += widths[index] + spacing
            }
        }

        private func columnWidths(for width: CGFloat?, count: Int) -> [CGFloat] {
            guard count > 0 else { return [] }
            let shares = (0 ..< count).map { $0 < weights.count ? weights[$0] : 1 }
            let sum = shares.reduce(0, +)
            guard let width, sum > 0 else { return shares.map { _ in Spacing.huge * 2 } }
            let available = max(width - spacing * CGFloat(count - 1), 0)
            return shares.map { available * $0 / sum }
        }
    }
#endif
