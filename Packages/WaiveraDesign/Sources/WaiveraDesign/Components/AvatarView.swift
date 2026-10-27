#if canImport(UIKit)
    import SwiftUI

    /// A person's avatar. Shows `image` when the caller has one (from the avatar cache), otherwise
    /// initials, otherwise a person glyph. A milestone adds a ring and is spoken, so the state is
    /// not carried by colour alone.
    public struct AvatarView: View {
        private let name: String
        private let image: Image?
        private let size: CGFloat
        private let rounded: Bool
        private let milestoneLabel: String?

        public init(
            name: String,
            image: Image? = nil,
            size: CGFloat = ControlSize.avatarMedium,
            rounded: Bool = false,
            milestoneLabel: String? = nil
        ) {
            self.name = name
            self.image = image
            self.size = size
            self.rounded = rounded
            self.milestoneLabel = milestoneLabel
        }

        public var body: some View {
            content
                .frame(width: size, height: size)
                .background(Palette.surfaceMuted)
                .clipShape(innerShape)
                .padding(milestoneLabel == nil ? 0 : ringInset)
                .overlay {
                    if milestoneLabel != nil {
                        outerShape.strokeBorder(Palette.milestone, lineWidth: ControlSize.milestoneRingWidth)
                    }
                }
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
                Text(initials)
                    .font(WaiveraFont.label)
                    .foregroundStyle(Palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(size * 0.15)
            } else {
                Image(systemName: "person.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Palette.textSecondary)
                    .frame(
                        width: AvatarGeometry.fallbackGlyphSize(size: size),
                        height: AvatarGeometry.fallbackGlyphSize(size: size)
                    )
            }
        }

        private var initials: String { AvatarGeometry.initials(for: name) }

        private var ringInset: CGFloat { ControlSize.milestoneRingWidth * 2 }

        private var innerShape: RoundedRectangle {
            RoundedRectangle(
                cornerRadius: AvatarGeometry.cornerRadius(size: size, rounded: rounded),
                style: .continuous
            )
        }

        private var outerShape: RoundedRectangle {
            let outer = size + ringInset * 2
            return RoundedRectangle(
                cornerRadius: AvatarGeometry.cornerRadius(size: outer, rounded: rounded),
                style: .continuous
            )
        }

        private var accessibilityText: String {
            guard let milestoneLabel else { return name }
            return "\(name), \(milestoneLabel)"
        }
    }

    private struct AvatarGallery: View {
        var body: some View {
            HStack(spacing: Spacing.medium) {
                AvatarView(name: "Alex Rivera")
                AvatarView(name: "Priya Raman", rounded: true)
                AvatarView(name: "", size: ControlSize.avatarSmall)
                AvatarView(
                    name: "Jordan Lee",
                    size: ControlSize.avatarLarge,
                    rounded: true,
                    milestoneLabel: "Birthday today"
                )
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { AvatarGallery() }
    #Preview("Dark") { AvatarGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { AvatarGallery().dynamicTypeSize(.accessibility5) }
#endif
