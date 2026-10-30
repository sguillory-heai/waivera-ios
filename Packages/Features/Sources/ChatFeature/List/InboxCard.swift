#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    extension InboxCardPosition {
        /// The row's piece of the inbox card: the first row takes the top corners, the last the
        /// bottom ones, a lone row all four.
        var shape: UnevenRoundedRectangle {
            let top = roundsTop ? Radius.sheetCard : 0
            let bottom = roundsBottom ? Radius.sheetCard : 0
            return UnevenRoundedRectangle(
                topLeadingRadius: top,
                bottomLeadingRadius: bottom,
                bottomTrailingRadius: bottom,
                topTrailingRadius: top,
                style: .continuous
            )
        }
    }

    /// A row's `listRowBackground`: the page, the row's piece of the card inset by the gutter,
    /// and the divider under every row but the last, inset past the leading tile. It stays
    /// still while the row itself dips under a press.
    struct InboxCardBackground: View {
        let position: InboxCardPosition

        var body: some View {
            ZStack(alignment: .bottom) {
                Palette.background
                position.shape
                    .fill(Palette.surface)
                    .padding(.horizontal, Spacing.gutter)
                if !position.isLast {
                    Rectangle()
                        .fill(Palette.border)
                        .frame(height: Spacing.hairline)
                        .padding(.leading, Spacing.gutter + Spacing.gutter + ControlSize.iconTile + Spacing.mediumSmall)
                        .padding(.trailing, Spacing.gutter)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Six rows of tile, two text bones of varying width and a time bone (02 §8), on the inbox
    /// card, so loaded rows settle in where the bones were.
    struct ChatListSkeleton: View {
        private static let titleWidths: [CGFloat] = [0.52, 0.38, 0.61, 0.45, 0.33, 0.56]
        private static let previewWidths: [CGFloat] = [0.82, 0.68, 0.74, 0.9, 0.6, 0.77]

        var rows = 6

        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { index in
                    HStack(spacing: Spacing.mediumSmall) {
                        SkeletonBlock(
                            width: ControlSize.iconTile,
                            height: ControlSize.iconTile,
                            cornerRadius: AvatarGeometry.cornerRadius(size: ControlSize.iconTile)
                        )
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            bone(Self.titleWidths[index % Self.titleWidths.count])
                            bone(Self.previewWidths[index % Self.previewWidths.count])
                        }
                        SkeletonBlock(width: Spacing.extraLarge, height: ControlSize.skeletonLine)
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.mediumSmall)
                    .frame(minHeight: ControlSize.listRowMinHeight)
                }
            }
            .background(Palette.surface, in: InboxCardPosition.single.shape)
            .padding(.horizontal, Spacing.gutter)
            .accessibilityElement()
            .accessibilityLabel(Text(ChatListStrings.string("chat.list.loading")))
        }

        private func bone(_ fraction: CGFloat) -> some View {
            GeometryReader { proxy in
                SkeletonBlock(width: proxy.size.width * fraction, height: ControlSize.skeletonLine)
            }
            .frame(height: ControlSize.skeletonLine)
        }
    }

    #if DEBUG
        #Preview("Light") { ChatListSkeleton().padding(.vertical, Spacing.medium).background(Palette.background) }
        #Preview("Dark") {
            ChatListSkeleton().padding(.vertical, Spacing.medium).background(Palette.background)
                .preferredColorScheme(.dark)
        }
        #Preview("AX5") {
            ChatListSkeleton().padding(.vertical, Spacing.medium).background(Palette.background)
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
