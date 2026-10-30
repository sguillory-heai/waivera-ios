#if canImport(UIKit)
    import SwiftUI

    /// A filter chip (Android `WaiveraFilterChip`, v5 decision 5 option A). Selected is the solid
    /// violet fill with white ink, the bold weight and a leading check, flat (no sheen or glow);
    /// at rest it is the surface with a hairline. It draws 36pt tall and keeps a 44pt target.
    /// No haptic.
    public struct ChipView: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let title: String
        private let isSelected: Bool
        private let systemImage: String?
        private let action: () -> Void

        public init(_ title: String, isSelected: Bool, systemImage: String? = nil, action: @escaping () -> Void) {
            self.title = title
            self.isSelected = isSelected
            self.systemImage = systemImage
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                HStack(spacing: Spacing.extraSmall + Spacing.xxSmall) {
                    if filled {
                        Image(systemName: "checkmark")
                            .font(.system(size: ControlSize.filterChipIcon * 0.75, weight: .bold))
                            .transition(Motion.pop(reduceMotion: reduceMotion))
                            .accessibilityHidden(true)
                    } else if let systemImage {
                        Image(systemName: systemImage)
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .waiveraTextStyle(.labelMedium)
                        .fontWeight(filled ? .bold : nil)
                        .lineLimit(1)
                        .padding(.vertical, Spacing.extraSmall)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, Spacing.mediumSmall + Spacing.xxSmall)
                .frame(minHeight: ControlSize.filterChipHeight)
                .background(fill, in: shape)
                .overlay {
                    if !filled {
                        shape.strokeBorder(
                            isSelected ? Palette.borderStrong : Palette.border,
                            lineWidth: isSelected ? ControlSize.selectedOutline : Spacing.hairline
                        )
                    }
                }
                .frame(minHeight: ControlSize.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .waiveraAnimation(.state, value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var filled: Bool { isSelected && isEnabled }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Radius.filterChip, style: .continuous)
        }

        private var ink: Color {
            if !isEnabled { return Palette.textSecondary }
            return filled ? Palette.onSelectedFill : Palette.text
        }

        private var fill: Color {
            if filled { return Palette.selectedFill }
            return isSelected ? Palette.surfaceMuted : Palette.surface
        }
    }

    /// A single-choice row of chips (the `All | Unread | Channels` filter). Scrolls sideways when
    /// the chips do not fit. No haptic.
    public struct SegmentedChips<Value: Hashable>: View {
        public struct Option {
            public let value: Value
            public let title: String

            public init(_ value: Value, title: String) {
                self.value = value
                self.title = title
            }
        }

        private let options: [Option]
        @Binding private var selection: Value

        public init(options: [Option], selection: Binding<Value>) {
            self.options = options
            _selection = selection
        }

        public var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.small) {
                    ForEach(options, id: \.value) { option in
                        ChipView(option.title, isSelected: option.value == selection) {
                            selection = option.value
                        }
                    }
                }
                .padding(.horizontal, Spacing.medium)
            }
        }
    }

    /// A segmented control (Android `WaiveraSegmentedControl`): segments on a muted track, the
    /// chosen one solid violet with white ink in the heavier weight, fading in on the state spring.
    /// Segments share the row equally while the widest fits, then by their own widths, then the
    /// row scrolls (`SegmentFit`). No haptic.
    public struct SegmentedControl<Value: Hashable>: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let options: [SegmentedChips<Value>.Option]
        @Binding private var selection: Value

        public init(options: [SegmentedChips<Value>.Option], selection: Binding<Value>) {
            self.options = options
            _selection = selection
        }

        public var body: some View {
            ViewThatFits(in: .horizontal) {
                track(equal: true)
                track(equal: false)
                ScrollView(.horizontal, showsIndicators: false) { track(equal: false) }
            }
        }

        private func track(equal: Bool) -> some View {
            HStack(spacing: Spacing.extraSmall) {
                ForEach(options, id: \.value) { option in
                    segment(option)
                        .frame(maxWidth: equal ? .infinity : nil)
                }
            }
            .padding(Spacing.extraSmall)
            .background(
                Palette.surfaceMuted,
                in: RoundedRectangle(cornerRadius: Radius.segmentTrack, style: .continuous)
            )
        }

        private func segment(_ option: SegmentedChips<Value>.Option) -> some View {
            let isSelected = option.value == selection
            return Button {
                if !isSelected { selection = option.value }
            } label: {
                Text(option.title)
                    .waiveraTextStyle(.labelLarge)
                    .fontWeight(isSelected ? .heavy : .semibold)
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isSelected ? Palette.onSelectedFill : Palette.textSecondary)
                    .padding(Spacing.small)
                    .frame(maxWidth: .infinity, minHeight: ControlSize.segmentMinHeight)
                    .background {
                        RoundedRectangle(cornerRadius: Radius.segment, style: .continuous)
                            .fill(Palette.selectedFill)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private struct ChipsGallery: View {
        @State private var filter = "All"
        @State private var period = "Week"

        var body: some View {
            VStack(spacing: Spacing.medium) {
                SegmentedChips(
                    options: ["All", "Unread", "Channels"].map { SegmentedChips<String>.Option($0, title: $0) },
                    selection: $filter
                )
                SegmentedControl(
                    options: ["Day", "Week", "Month"].map { SegmentedChips<String>.Option($0, title: $0) },
                    selection: $period
                )
                .padding(.horizontal, Spacing.medium)
                ChipView("Disabled", isSelected: true) {}.disabled(true)
            }
            .padding(.vertical, Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { ChipsGallery() }
    #Preview("Dark") { ChipsGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { ChipsGallery().dynamicTypeSize(.accessibility5) }
#endif
