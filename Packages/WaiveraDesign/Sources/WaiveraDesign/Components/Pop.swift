#if canImport(UIKit)
    import SwiftUI

    public extension View {
        /// Pops (from `MotionTiming.popStartScale` back to full size on the pop spring) each time
        /// `key` changes, so a count or glyph that moves is seen to. Still under Reduce Motion.
        func popOnChange(of key: some Equatable) -> some View {
            modifier(PopOnChange(key: key))
        }
    }

    private struct PopOnChange<Key: Equatable>: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let key: Key
        @State private var pops = 0

        func body(content: Content) -> some View {
            content
                .keyframeAnimator(initialValue: 1.0, trigger: pops) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        MoveKeyframe(MotionTiming.popStartScale)
                        SpringKeyframe(
                            1.0,
                            duration: MotionSpec.pop.settlingTime(),
                            spring: Spring(
                                response: MotionSpec.pop.response,
                                dampingRatio: MotionSpec.pop.dampingFraction
                            )
                        )
                    }
                }
                .onChange(of: key) {
                    if !reduceMotion { pops += 1 }
                }
        }
    }

    /// Shows `content` while `isVisible`, popping in and shrinking away instead of appearing and
    /// vanishing (Android `WaiveraPopVisibility`). A short fade under Reduce Motion.
    public struct PopVisibility<Content: View>: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let isVisible: Bool
        private let content: Content

        public init(isVisible: Bool, @ViewBuilder content: () -> Content) {
            self.isVisible = isVisible
            self.content = content()
        }

        public var body: some View {
            ZStack {
                if isVisible {
                    content.transition(Motion.pop(reduceMotion: reduceMotion))
                }
            }
            .animation(Motion.animation(MotionPolicy.pop(reduceMotion: reduceMotion)), value: isVisible)
        }
    }

    /// Shows and hides `content` by growing and shrinking its height on the layout spring
    /// (Android `WaiveraExpand`); fades under Reduce Motion. Use for rows that join or leave a list.
    public struct Expand<Content: View>: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let isExpanded: Bool
        private let content: Content

        public init(isExpanded: Bool, @ViewBuilder content: () -> Content) {
            self.isExpanded = isExpanded
            self.content = content()
        }

        public var body: some View {
            VStack(spacing: 0) {
                if isExpanded {
                    content.transition(
                        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
                    )
                }
            }
            .clipped()
            .animation(Motion.animation(.layout, reduceMotion: reduceMotion) ?? .linear(duration: 0), value: isExpanded)
        }
    }

    private struct PopGallery: View {
        @State private var count = 3
        @State private var shown = true

        var body: some View {
            VStack(spacing: Spacing.large) {
                Button("Add one") { count += 1 }
                Text(verbatim: "\(count)")
                    .waiveraTextStyle(.ringNumeral)
                    .popOnChange(of: count)
                Button("Toggle") { shown.toggle() }
                PopVisibility(isVisible: shown) {
                    CountBadge(count: count)
                }
                Expand(isExpanded: shown) {
                    Text(verbatim: "A row that joins the list")
                        .padding(Spacing.medium)
                }
            }
            .padding(Spacing.large)
            .background(Palette.background)
        }
    }

    #Preview("Light") { PopGallery() }
    #Preview("Dark") { PopGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { PopGallery().dynamicTypeSize(.accessibility5) }
#endif
