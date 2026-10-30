#if canImport(UIKit)
    import SwiftUI

    /// A placeholder block (Android `WaiveraSkeleton`): its colour breathes between the skeleton
    /// base and highlight on a 900ms eased pulse, or holds the base under Reduce Motion.
    public struct SkeletonBlock: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.waiveraEndlessMotionDisabled) private var endlessMotionDisabled
        @ScaledMetric(relativeTo: .body) private var lineHeight = ControlSize.skeletonLine
        @State private var isLit = false

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
                .fill(Palette.skeletonBase)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Palette.skeletonHighlight)
                        .opacity(isLit && animates ? 1 : 0)
                }
                .frame(width: width, height: height ?? lineHeight)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
                .onAppear(perform: startPulse)
                .onChange(of: reduceMotion) { startPulse() }
                .accessibilityHidden(true)
        }

        private var animates: Bool {
            !endlessMotionDisabled && MotionPolicy.skeletonAnimates(reduceMotion: reduceMotion)
        }

        private func startPulse() {
            guard animates else {
                isLit = false
                return
            }
            let pulse = Motion.animation(MotionSpec.skeletonPulse).repeatForever(autoreverses: true)
            withAnimation(pulse) { isLit = true }
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
                    HStack(spacing: Spacing.mediumSmall) {
                        SkeletonBlock(
                            width: ControlSize.avatarMedium,
                            height: ControlSize.avatarMedium,
                            cornerRadius: AvatarGeometry.cornerRadius(size: ControlSize.avatarMedium)
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

    /// Shows `skeleton` only for loads slower than ~300ms and keeps it at least ~300ms once shown,
    /// so fast responses never flash a placeholder. The skeleton hands over to the content with the
    /// swap's fade-through (the skeleton leaves on the quick exit, the content fades in after it).
    public struct LoadingContent<Content: View, Skeleton: View>: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .transition(.opacity.animation(Motion.animation(MotionPolicy.exit(reduceMotion: reduceMotion))))
                } else if !isLoading {
                    content
                        .transition(
                            .opacity.animation(
                                Motion.animation(MotionPolicy.enterAfterExit(reduceMotion: reduceMotion))
                            )
                        )
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

    private struct SkeletonGallery: View {
        @State private var loading = true

        var body: some View {
            VStack {
                Button("Toggle load") { loading.toggle() }
                LoadingContent(isLoading: loading) {
                    Text(verbatim: "Loaded content")
                        .padding(Spacing.medium)
                } skeleton: {
                    SkeletonList(rows: 4)
                }
            }
            .background(Palette.background)
        }
    }

    #Preview("Light") { SkeletonGallery() }
    #Preview("Dark") { SkeletonGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { SkeletonGallery().dynamicTypeSize(.accessibility5) }
#endif
