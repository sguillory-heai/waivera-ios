#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Lines of text while a file loads (Android `LoadingPage`): nine body lines, every third
    /// one short, so the placeholder reads as a page rather than a list of people.
    struct DocumentSkeleton: View {
        static let lines = 9

        /// A short line's share of the width, as Android's `SKELETON_SHORT`.
        static let shortShare: CGFloat = 0.6

        var body: some View {
            GeometryReader { proxy in
                let width = max(0, proxy.size.width - Spacing.gutter * 2)
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(0..<Self.lines, id: \.self) { line in
                        SkeletonBlock(width: line % 3 == 2 ? width * Self.shortShare : width)
                    }
                }
                .padding(Spacing.gutter)
            }
        }
    }
#endif
