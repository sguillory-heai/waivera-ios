#if canImport(UIKit)
    import SwiftUI

    /// A filter chip. The visible pill is compact; the hit target is at least 44pt tall.
    public struct ChipView: View {
        private let title: String
        private let isSelected: Bool
        private let action: () -> Void

        public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
            self.title = title
            self.isSelected = isSelected
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                Text(title)
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(isSelected ? Palette.onAccent : Palette.text)
                    .padding(.horizontal, Spacing.smallPlus)
                    .padding(.vertical, Spacing.small)
                    .background(isSelected ? Palette.accent : Palette.surfaceMuted, in: Capsule())
                    .overlay {
                        if !isSelected {
                            Capsule().strokeBorder(Palette.border, lineWidth: Spacing.hairline)
                        }
                    }
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .waiveraAnimation(.state, value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    /// A single-choice row of chips (the `All | Unread | Channels` filter, Day/Week/Month).
    /// Plays the selection haptic when the choice changes.
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
            .waiveraHaptic(.selection, trigger: selection)
        }
    }

    private struct ChipsGallery: View {
        @State private var filter = "All"

        var body: some View {
            SegmentedChips(
                options: ["All", "Unread", "Channels"].map { SegmentedChips<String>.Option($0, title: $0) },
                selection: $filter
            )
            .padding(.vertical, Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { ChipsGallery() }
    #Preview("Dark") { ChipsGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { ChipsGallery().dynamicTypeSize(.accessibility5) }
#endif
