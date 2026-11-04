#if canImport(UIKit)
    import SwiftUI

    /// A person's avatar (Android `WaiveraAvatar`). Every avatar is the same soft rounded square,
    /// never a circle and never bordered: `image` when the caller has one (from the avatar cache),
    /// otherwise bold initials sized from the avatar (not the text size), otherwise a person
    /// glyph, on the person's own tile (`AvatarTiles`, the gradient Android uses too). A milestone is spoken with the name; the schedule's milestone badge
    /// draws it.
    public struct AvatarView: View {
        public enum Fill: Sendable {
            /// The person's gradient tile with white initials.
            case standard
            /// The hero's glass with white initials (the account button on the plum hero).
            case hero
        }

        private let name: String
        private let image: Image?
        private let size: CGFloat
        private let fill: Fill
        private let milestoneLabel: String?
        private let tileIndex: Int?

        /// `tileIndex` picks one of `AvatarTiles.pairs` for every name (a picker colouring people
        /// by kind); left out, the name picks the tile.
        public init(
            name: String,
            image: Image? = nil,
            size: CGFloat = ControlSize.avatarMedium,
            fill: Fill = .standard,
            milestoneLabel: String? = nil,
            tileIndex: Int? = nil
        ) {
            self.tileIndex = tileIndex
            self.name = name
            self.image = image
            self.size = size
            self.fill = fill
            self.milestoneLabel = milestoneLabel
        }

        public var body: some View {
            content
                .frame(width: size, height: size)
                .background { background }
                .clipShape(shape)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityText))
                .accessibilityAddTraits(.isImage)
        }

        @ViewBuilder private var content: some View {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else if !initials.isEmpty {
                // The avatar is a fixed-size image, so its initials do not follow Dynamic Type.
                Text(initials)
                    .font(
                        .custom(
                            FontWeightToken.bold.postScriptName,
                            fixedSize: AvatarGeometry.initialsFontSize(size: size)
                        )
                    )
                    .foregroundStyle(inkColor)
                    .shadow(
                        color: fill == .standard ? Color(rgb: AvatarTiles.shadow) : .clear,
                        radius: size * AvatarTiles.shadowBlur,
                        x: 0,
                        y: size * AvatarTiles.shadowDrop
                    )
                    .lineLimit(1)
                    .accessibilityIdentifier("fixedTextSize.avatarInitials")
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.1)
            } else {
                Image(waivera: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(inkColor)
                    .frame(
                        width: AvatarGeometry.fallbackGlyphSize(size: size),
                        height: AvatarGeometry.fallbackGlyphSize(size: size)
                    )
            }
        }

        private var initials: String { AvatarGeometry.initials(for: name) }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: AvatarGeometry.cornerRadius(size: size), style: .continuous)
        }

        /// No tile behind a photo, so a transparent picture never shows a colour through.
        @ViewBuilder private var background: some View {
            switch fill {
            case .hero: HeroPalette.accountFill
            case .standard where image != nil: Palette.avatarFill
            case .standard: tile
            }
        }

        /// Gradient, a sheen over the top and a faint inner edge (Android `personTile`).
        private var tile: some View {
            var pair = AvatarTiles.pair(for: name)
            if let tileIndex { pair = AvatarTiles.pairs[tileIndex % AvatarTiles.pairs.count] }
            let edge = size * AvatarTiles.edgeFraction
            return ZStack {
                LinearGradient(
                    colors: [Color(rgb: pair.start), Color(rgb: pair.end)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(AvatarTiles.sheenOpacity), .clear],
                    center: UnitPoint(x: 0.5, y: -AvatarTiles.sheenCenter),
                    startRadius: 0,
                    endRadius: size * AvatarTiles.sheenRadius
                )
                shape
                    .inset(by: edge / 2)
                    .stroke(Color.white.opacity(AvatarTiles.edgeOpacity), lineWidth: edge)
            }
        }

        private var inkColor: Color {
            switch fill {
            case .standard: .white
            case .hero: HeroPalette.onHeader
            }
        }

        private var accessibilityText: String {
            guard let milestoneLabel else { return name }
            return "\(name), \(milestoneLabel)"
        }
    }

    private struct AvatarGallery: View {
        var body: some View {
            VStack(spacing: Spacing.medium) {
                HStack(spacing: Spacing.medium) {
                    AvatarView(name: "Alex Rivera", size: ControlSize.avatarSmall)
                    AvatarView(name: "Priya Raman")
                    AvatarView(name: "", size: ControlSize.avatarMedium)
                    AvatarView(name: "Jordan Lee", size: ControlSize.avatarLarge, milestoneLabel: "Birthday today")
                }
                AvatarView(name: "Sam Okafor", size: HeroMetrics.barAvatar, fill: .hero)
                    .padding(Spacing.small)
                    .background(HeroPalette.headerBottom)
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { AvatarGallery() }
    #Preview("Dark") { AvatarGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { AvatarGallery().dynamicTypeSize(.accessibility5) }
#endif
