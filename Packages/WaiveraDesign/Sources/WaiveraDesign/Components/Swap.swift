#if canImport(UIKit)
    import SwiftUI

    /// Swaps content in place with Android's fade-through (`WaiveraSwap`): the old side leaves on
    /// the 60ms exit, the new side fades in 40ms later over 150ms while it grows from 92% on the
    /// pop spring. With an `axis` the new side also slides in from a third of the width (a period
    /// step) or half the height (a count roll), from the side `forward` names. Under Reduce Motion
    /// it is a plain cross-fade.
    public struct SwapView<Value: Hashable, Content: View>: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let value: Value
        private let axis: SwapAxis?
        private let forward: Bool
        private let content: (Value) -> Content

        public init(
            _ value: Value,
            axis: SwapAxis? = nil,
            forward: Bool = true,
            @ViewBuilder content: @escaping (Value) -> Content
        ) {
            self.value = value
            self.axis = axis
            self.forward = forward
            self.content = content
        }

        public var body: some View {
            ZStack {
                content(value)
                    .id(value)
                    .transition(transition)
            }
            .animation(Motion.animation(MotionPolicy.swapEnter(reduceMotion: reduceMotion)), value: value)
        }

        private var transition: AnyTransition {
            let exit = AnyTransition.opacity.animation(
                Motion.animation(MotionPolicy.swapExit(reduceMotion: reduceMotion))
            )
            let fadeIn = AnyTransition.opacity.animation(
                Motion.animation(MotionPolicy.swapEnter(reduceMotion: reduceMotion))
            )
            guard MotionPolicy.swapMoves(reduceMotion: reduceMotion) else {
                return .asymmetric(insertion: fadeIn, removal: exit)
            }
            let pop = Motion.animation(MotionSpec.pop)
            var insertion = fadeIn.combined(
                with: AnyTransition.scale(scale: MotionTiming.swapStartScale).animation(pop)
            )
            if let axis {
                let slide = AnyTransition.modifier(
                    active: SwapSlide(axis: axis, sign: forward ? 1 : -1),
                    identity: SwapSlide(axis: axis, sign: 0)
                )
                insertion = insertion.combined(with: slide.animation(pop))
            }
            return .asymmetric(insertion: insertion, removal: exit)
        }
    }

    /// Offsets an arriving side by a share of its own size: a third across, or half up or down.
    private struct SwapSlide: ViewModifier {
        let axis: SwapAxis
        let sign: CGFloat

        func body(content: Content) -> some View {
            let axis = axis
            let sign = sign
            return content.visualEffect { effect, proxy in
                let across = axis == .horizontal
                let x = across ? sign * proxy.size.width / CGFloat(MotionTiming.swapSlideDivisor) : 0
                let y = across ? 0 : sign * proxy.size.height / CGFloat(MotionTiming.swapRollDivisor)
                return effect.offset(x: x, y: y)
            }
        }
    }

    private struct SwapGallery: View {
        @State private var week = 42
        @State private var count = 5

        var body: some View {
            VStack(spacing: Spacing.large) {
                SwapView(week, axis: .horizontal) { value in
                    Text(verbatim: "Week \(value)").waiveraTextStyle(.titleLarge)
                }
                Button("Next week") { week += 1 }
                SwapView(count, axis: .vertical) { value in
                    Text(verbatim: "\(value)").waiveraTextStyle(.ringNumeral)
                }
                Button("Count up") { count += 1 }
            }
            .foregroundStyle(Palette.text)
            .padding(Spacing.large)
            .background(Palette.background)
        }
    }

    #Preview("Light") { SwapGallery() }
    #Preview("Dark") { SwapGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { SwapGallery().dynamicTypeSize(.accessibility5) }
#endif
