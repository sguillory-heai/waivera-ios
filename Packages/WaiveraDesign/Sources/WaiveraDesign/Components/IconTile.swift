#if canImport(UIKit)
    import SwiftUI

    /// A soft rounded tile holding a glyph, tinted by what it is about (`TileTone`: one meaning per
    /// tint on every screen). Decorative: the row it leads says what it is.
    public struct IconTile: View {
        private let systemImage: String
        private let tone: TileTone
        private let size: CGFloat
        private let glyphSize: CGFloat

        public init(
            systemImage: String,
            tone: TileTone = .brand,
            size: CGFloat = ControlSize.iconTile,
            glyphSize: CGFloat = ControlSize.icon
        ) {
            self.systemImage = systemImage
            self.tone = tone
            self.size = size
            self.glyphSize = glyphSize
        }

        public var body: some View {
            TileFrame(tone: tone, size: size) {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .foregroundStyle(tone.contentColor)
                    .frame(width: glyphSize * 0.8, height: glyphSize * 0.8)
            }
        }
    }

    /// A tile holding an emoji, for celebrations (`TileTone.celebration`).
    public struct EmojiTile: View {
        private let emoji: String
        private let tone: TileTone
        private let size: CGFloat

        public init(_ emoji: String, tone: TileTone = .celebration, size: CGFloat = ControlSize.iconTile) {
            self.emoji = emoji
            self.tone = tone
            self.size = size
        }

        public var body: some View {
            TileFrame(tone: tone, size: size) {
                Text(emoji)
                    .font(
                        .system(
                            size: size >= ControlSize.iconTile ? ControlSize.emojiInTile : ControlSize.emojiInTileSmall
                        )
                    )
                    .dynamicTypeSize(.large)
            }
        }
    }

    /// The Waivera mark on a brand tile (the app's own notices).
    public struct LogoTile: View {
        private let size: CGFloat

        public init(size: CGFloat = ControlSize.iconTile) {
            self.size = size
        }

        public var body: some View {
            TileFrame(tone: .brand, size: size) {
                WaiveraLogo(style: .mark)
                    .frame(height: ControlSize.icon)
            }
        }
    }

    private struct TileFrame<Content: View>: View {
        let tone: TileTone
        let size: CGFloat
        @ViewBuilder let content: Content

        var body: some View {
            content
                .frame(width: size, height: size)
                .background(tone.containerColor, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private struct IconTileGallery: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                HStack(spacing: Spacing.small) {
                    ForEach(TileTone.allCases, id: \.self) { tone in
                        IconTile(systemImage: "calendar", tone: tone)
                    }
                }
                HStack(spacing: Spacing.small) {
                    EmojiTile("🎂")
                    IconTile(
                        systemImage: "bell",
                        tone: .amber,
                        size: ControlSize.iconTileSmall,
                        glyphSize: ControlSize.iconTileSmallGlyph
                    )
                    LogoTile()
                }
            }
            .padding(Spacing.medium)
            .background(Palette.surface)
        }
    }

    #Preview("Light") { IconTileGallery() }
    #Preview("Dark") { IconTileGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { IconTileGallery().dynamicTypeSize(.accessibility5) }
#endif
