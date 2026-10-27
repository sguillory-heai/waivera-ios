#if canImport(UIKit)
    import SwiftUI

    /// A tappable list row: optional leading view, title, subtitle, trailing view and chevron.
    /// Rows grow with Dynamic Type; titles wrap instead of truncating.
    public struct ListRow<Leading: View, Trailing: View>: View {
        private let title: String
        private let subtitle: String?
        private let showsChevron: Bool
        private let leading: Leading
        private let trailing: Trailing

        public init(
            title: String,
            subtitle: String? = nil,
            showsChevron: Bool = false,
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder trailing: () -> Trailing
        ) {
            self.title = title
            self.subtitle = subtitle
            self.showsChevron = showsChevron
            self.leading = leading()
            self.trailing = trailing()
        }

        public var body: some View {
            HStack(spacing: Spacing.smallPlus) {
                leading
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(title)
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Spacing.smallPlus)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: ControlSize.minHitTarget)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    public extension ListRow where Leading == EmptyView, Trailing == EmptyView {
        init(title: String, subtitle: String? = nil, showsChevron: Bool = false) {
            self.init(
                title: title,
                subtitle: subtitle,
                showsChevron: showsChevron,
                leading: { EmptyView() },
                trailing: { EmptyView() }
            )
        }
    }

    public extension ListRow where Trailing == EmptyView {
        init(title: String, subtitle: String? = nil, showsChevron: Bool = false, @ViewBuilder leading: () -> Leading) {
            self.init(
                title: title,
                subtitle: subtitle,
                showsChevron: showsChevron,
                leading: leading,
                trailing: { EmptyView() }
            )
        }
    }

    private struct ListRowGallery: View {
        var body: some View {
            VStack(spacing: 0) {
                ListRow(title: "Notifications", subtitle: "Messages, mentions and schedule", showsChevron: true) {
                    IconTile(systemImage: "bell.fill")
                }
                Divider()
                ListRow(title: "Alex Rivera", subtitle: "can you cover Friday?") {
                    AvatarView(name: "Alex Rivera")
                } trailing: {
                    CountBadge(count: 3)
                }
                Divider()
                ListRow(title: "Appearance")
            }
            .background(Palette.surface)
        }
    }

    #Preview("Light") { ListRowGallery() }
    #Preview("Dark") { ListRowGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { ListRowGallery().dynamicTypeSize(.accessibility5) }
#endif
