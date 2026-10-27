#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// An avatar with the birthday / anniversary badge (07 §4 `MilestoneAvatar`). The badge is
    /// a glyph as well as a colour, and the whole avatar speaks the celebration sentence, or the
    /// person's name when there is nothing to celebrate.
    struct MilestoneAvatarView: View {
        let name: String
        let userId: String?
        let celebration: ScheduleCelebration?
        let size: CGFloat

        @Environment(\.dataEnvironment) private var data
        @State private var image: Image?

        var body: some View {
            AvatarView(name: name, image: image, size: size)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        MilestoneBadgeView(badge: badge)
                            .offset(x: badge.size * 0.28, y: -badge.size * 0.25)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(badge?.accessibilityLabel ?? name))
                .accessibilityAddTraits(.isImage)
                .task(id: userId) { await loadAvatar() }
        }

        private var badge: MilestoneBadge? {
            celebration.map { MilestoneBadge(celebration: $0, avatarSize: Double(size), name: name) }
        }

        private func loadAvatar() async {
            guard let userId, let data, let bytes = await data.avatars.avatar(userId: userId),
                let uiImage = UIImage(data: bytes)
            else { return }
            image = Image(uiImage: uiImage)
        }
    }
#endif
