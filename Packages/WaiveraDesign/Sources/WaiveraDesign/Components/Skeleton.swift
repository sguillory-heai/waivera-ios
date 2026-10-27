#if canImport(UIKit)
    import SwiftUI

    /// A placeholder block that pulses 0.45 ↔ 0.85, or holds a static tone under Reduce Motion.
    public struct SkeletonBlock: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @ScaledMetric(relativeTo: .body) private var lineHeight = ControlSize.skeletonLine
        @State private var isPulsing = false

        private let width: CGFloat?
        private let height: CGFloat?
        private let cornerRadius: CGFloat

        /// `height` nil means one line of body text at the current Dynamic Type size.
        public init(width: CGFloat? = nil, height: CGFloat? = nil, cornerRadius: CGFloat = Radius.chip) {
            self.width = width
            self.height = height
            self.cornerRadius = cornerRadius
        }

        public var body: some View {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Palette.surfaceMuted)
                .frame(width: width, height: height ?? lineHeight)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
                .opacity(opacity)
                .onAppear(perform: startPulse)
                .onChange(of: reduceMotion) { startPulse() }
                .accessibilityHidden(true)
        }

        private var animates: Bool { MotionPolicy.skeletonAnimates(reduceMotion: reduceMotion) }

        private var opacity: Double {
            let range = MotionPolicy.skeletonOpacityRange
            guard animates else { return (range.low + range.high) / 2 }
            return isPulsing ? range.high : range.low
        }

        private func startPulse() {
            guard animates else {
                isPulsing = false
                return
            }
            withAnimation(.easeInOut(duration: MotionPolicy.skeletonPulseDuration).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    /// A list skeleton shaped like avatar rows (conversation list, people, activity).
    public struct SkeletonList: View {
        private let rows: Int

        public init(rows: Int = 6) {
            self.rows = rows
        }

        public var body: some View {
            VStack(spacing: Spacing.medium) {
                ForEach(0..<rows, id: \.self) { index in
                    HStack(spacing: Spacing.smallPlus) {
                        SkeletonBlock(
                            width: ControlSize.avatarMedium,
                            height: ControlSize.avatarMedium,
                            cornerRadius: AvatarGeometry.cornerRadius(size: ControlSize.avatarMedium, rounded: false)
                        )
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            SkeletonBlock()
                            SkeletonBlock()
                                .padding(.trailing, index.isMultiple(of: 2) ? Spacing.huge : Spacing.extraLarge)
                        }
                    }
                }
            }
            .padding(Spacing.medium)
            .accessibilityElement()
            .accessibilityLabel(Text(DesignStrings.loading))
        }
    }

    /// Shows `skeleton` only for loads slower than ~300ms, and keeps it at least ~300ms once shown,
    /// so fast responses never flash a placeholder.
    public struct LoadingContent<Content: View, Skeleton: View>: View {
        private let isLoading: Bool
        private let timing: SkeletonTiming
        private let content: Content
        private let skeleton: Skeleton

        @State private var showsSkeleton = false
        @State private var skeletonShownAt: Date?

        public init(
            isLoading: Bool,
            timing: SkeletonTiming = .standard,
            @ViewBuilder content: () -> Content,
            @ViewBuilder skeleton: () -> Skeleton
        ) {
            self.isLoading = isLoading
            self.timing = timing
            self.content = content()
            self.skeleton = skeleton()
        }

        public var body: some View {
            ZStack {
                if showsSkeleton {
                    skeleton
                } else if !isLoading {
                    content
                }
            }
            .task(id: isLoading) {
                if isLoading {
                    try? await Task.sleep(for: .seconds(timing.showDelay))
                    guard !Task.isCancelled else { return }
                    showsSkeleton = true
                    skeletonShownAt = Date()
                } else if showsSkeleton {
                    let shownFor = skeletonShownAt.map { Date().timeIntervalSince($0) } ?? timing.minimumVisible
                    let remaining = timing.remainingVisible(shownFor: shownFor)
                    if remaining > 0 {
                        try? await Task.sleep(for: .seconds(remaining))
                    }
                    guard !Task.isCancelled else { return }
                    showsSkeleton = false
                    skeletonShownAt = nil
                }
            }
        }
    }

    #Preview("Light") { SkeletonList(rows: 4).background(Palette.background) }
    #Preview("Dark") { SkeletonList(rows: 4).background(Palette.background).preferredColorScheme(.dark) }
    #Preview("AX XXXL") { SkeletonList(rows: 4).background(Palette.background).dynamicTypeSize(.accessibility5) }
#endif
