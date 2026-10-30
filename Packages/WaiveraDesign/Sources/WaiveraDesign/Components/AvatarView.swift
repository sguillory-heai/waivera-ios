#if canImport(UIKit)
    import SwiftUI

    /// A person's avatar (Android `WaiveraAvatar`). Every avatar is the same soft rounded square,
    /// never a circle and never bordered: `image` when the caller has one (from the avatar cache),
    /// otherwise bold initials sized from the avatar (not the text size), otherwise a person
    /// glyph, on `avatarFill`. A milestone is spoken with the name; the schedule's milestone badge
    /// draws it.
    public struct AvatarView: View {
        public enum Fill: Sendable {
            /// `avatarFill` with the soft accent ink.
            case standard
            /// The hero's glass with white initials (the account button on the plum hero).
            case hero
        }

        private let name: String
        private let image: Image?
        private let size: CGFloat
        private let fill: Fill
        private let milestoneLabel: String?

        public init(
            name: String,
            image: Image? = nil,
            size: CGFloat = ControlSize.avatarMedium,
            fill: Fill = .standard,
            milestoneLabel: String? = nil
        ) {
            self.name = name
            self.image = image
            self.size = size
            self.fill = fill
            self.milestoneLabel = milestoneLabel
        }

        public var body: some View {
            content
                .frame(width: size, height: size)
                .background(fillColor)
                .clipShape(RoundedRectangle(cornerRadius: AvatarGeometry.cornerRadius(size: size), style: .continuous))
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.1)
            } else {
                Image(systemName: "person.fill")
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

        private var fillColor: Color {
            switch fill {
            case .standard: Palette.avatarFill
            case .hero: HeroPalette.accountFill
            }
        }

        private var inkColor: Color {
            switch fill {
            case .standard: Palette.onAccentSoft
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
