#if canImport(UIKit)
    import SwiftUI
    import UIKit

    /// How a row's title is set.
    public enum ListRowTitle: Sendable {
        /// A label that wraps as far as it needs (settings, schedule items).
        case wraps
        /// A chat name: one line, shrinking up to 15% before "…" (v7 item 3).
        case oneLineName
        /// A person's name as the row's headline: one line, two above 130% text (wave 29 N4).
        case personName
    }

    /// A tappable list row: optional leading view, title, subtitle, trailing view and chevron.
    /// The leading tile or avatar centres on a standard two-line row and pins level with the
    /// title's first line once long content makes the row taller (the leading-pin rule).
    public struct ListRow<Leading: View, Trailing: View>: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private let title: String
        private let subtitle: String?
        private let titleKind: ListRowTitle
        private let showsChevron: Bool
        private let leading: Leading
        private let trailing: Trailing

        public init(
            title: String,
            subtitle: String? = nil,
            titleKind: ListRowTitle = .wraps,
            showsChevron: Bool = false,
            @ViewBuilder leading: () -> Leading,
            @ViewBuilder trailing: () -> Trailing
        ) {
            self.title = title
            self.subtitle = subtitle
            self.titleKind = titleKind
            self.showsChevron = showsChevron
            self.leading = leading()
            self.trailing = trailing()
        }

        public var body: some View {
            LeadingPinLayout(spacing: Spacing.mediumSmall, standardHeight: standardHeight) {
                leading
                HStack(spacing: Spacing.mediumSmall) {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        titleView
                            .foregroundStyle(Palette.text)
                        if let subtitle {
                            Text(subtitle)
                                .waiveraTextStyle(.bodySmall)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailing
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(WaiveraFont.captionEmphasis)
                            .foregroundStyle(Palette.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .leadingPinContent()
            }
            .padding(.vertical, Spacing.mediumSmall)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: ControlSize.listRowMinHeight)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder private var titleView: some View {
            switch titleKind {
            case .wraps:
                Text(title).waiveraTextStyle(.titleSmall)
            case .oneLineName:
                OneLineName(title, style: .titleSmall)
            case .personName:
                NameText(title, style: .titleSmall, lines: NameLines.listRow(dynamicTypeSize.category))
            }
        }

        /// A title line, the 2pt gap and a subtitle line plus half a line of slack, at this size.
        private var standardHeight: CGFloat {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
            return CGFloat(
                LeadingTileAlignment.twoLineRowContentHeight(
                    titleLine: Double(TextStyleToken.titleSmall.scaledLineHeight(compatibleWith: traits)),
                    gap: Double(Spacing.xxSmall),
                    subtitleLine: Double(TextStyleToken.bodySmall.scaledLineHeight(compatibleWith: traits))
                )
            )
        }
    }

    public extension ListRow where Leading == EmptyView, Trailing == EmptyView {
        init(title: String, subtitle: String? = nil, titleKind: ListRowTitle = .wraps, showsChevron: Bool = false) {
            self.init(
                title: title,
                subtitle: subtitle,
                titleKind: titleKind,
                showsChevron: showsChevron,
                leading: { EmptyView() },
                trailing: { EmptyView() }
            )
        }
    }

    public extension ListRow where Trailing == EmptyView {
        init(
            title: String,
            subtitle: String? = nil,
            titleKind: ListRowTitle = .wraps,
            showsChevron: Bool = false,
            @ViewBuilder leading: () -> Leading
        ) {
            self.init(
                title: title,
                subtitle: subtitle,
                titleKind: titleKind,
                showsChevron: showsChevron,
                leading: leading,
                trailing: { EmptyView() }
            )
        }
    }

    private struct LeadingPinContentKey: LayoutValueKey {
        static let defaultValue = false
    }

    public extension View {
        /// Marks the row content inside a `LeadingPinLayout`; the other subview is the leading view.
        func leadingPinContent() -> some View {
            layoutValue(key: LeadingPinContentKey.self, value: true)
        }
    }

    /// Lays out a leading view and the row's content side by side, placing the leading view by
    /// `LeadingTileAlignment` (measured heights, never a count of lines). Mark the content with
    /// `leadingPinContent()`; the leading view may be absent.
    public struct LeadingPinLayout: Layout {
        private let spacing: CGFloat
        private let standardHeight: CGFloat

        public init(spacing: CGFloat = Spacing.mediumSmall, standardHeight: CGFloat) {
            self.spacing = spacing
            self.standardHeight = standardHeight
        }

        public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let parts = measure(proposal: proposal, subviews: subviews)
            return CGSize(width: parts.width, height: parts.height)
        }

        public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void)
        {
            let parts = measure(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
            if let leading = leadingView(subviews) {
                leading.place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY + parts.leadingY),
                    proposal: ProposedViewSize(parts.leadingSize)
                )
            }
            if let content = contentView(subviews) {
                let contentX = bounds.minX + parts.contentX
                content.place(
                    at: CGPoint(x: contentX, y: bounds.minY + parts.contentY),
                    proposal: ProposedViewSize(width: bounds.maxX - contentX, height: parts.contentHeight)
                )
            }
        }

        private func leadingView(_ subviews: Subviews) -> LayoutSubview? {
            subviews.first { !$0[LeadingPinContentKey.self] }
        }

        private func contentView(_ subviews: Subviews) -> LayoutSubview? {
            subviews.first { $0[LeadingPinContentKey.self] }
        }

        private struct Parts {
            var width: CGFloat
            var height: CGFloat
            var leadingSize: CGSize
            var leadingY: CGFloat
            var contentX: CGFloat
            var contentY: CGFloat
            var contentHeight: CGFloat
        }

        private func measure(proposal: ProposedViewSize, subviews: Subviews) -> Parts {
            let leadingSize = leadingView(subviews)?.sizeThatFits(.unspecified) ?? .zero
            let hasLeading = leadingSize.width > 0
            let contentX = hasLeading ? leadingSize.width + spacing : 0
            let contentWidth = proposal.width.map { max(0, $0 - contentX) }
            let contentSize =
                contentView(subviews)?.sizeThatFits(ProposedViewSize(width: contentWidth, height: nil)) ?? .zero
            let height = max(contentSize.height, leadingSize.height)
            let leadingY: CGFloat
            let contentY: CGFloat
            if leadingSize.height >= contentSize.height {
                // A tile taller than the text: the text centres on the tile.
                leadingY = 0
                contentY = ((height - contentSize.height) / 2).rounded()
            } else {
                leadingY = CGFloat(
                    LeadingTileAlignment.offset(
                        tileHeight: Double(leadingSize.height),
                        contentHeight: Double(contentSize.height),
                        standardHeight: Double(standardHeight)
                    )
                )
                contentY = 0
            }
            return Parts(
                width: proposal.width ?? (contentX + contentSize.width),
                height: height,
                leadingSize: leadingSize,
                leadingY: leadingY,
                contentX: contentX,
                contentY: contentY,
                contentHeight: contentSize.height
            )
        }
    }

    /// A list section's heading (Android `WaiveraSectionHeader`): an uppercase eyebrow.
    public struct SectionHeader: View {
        private let title: String

        public init(_ title: String) {
            self.title = title
        }

        public var body: some View {
            Text(title.uppercased())
                .waiveraTextStyle(.eyebrow)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.medium)
                .padding(.top, Spacing.large)
                .padding(.bottom, Spacing.small)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Rows grouped on one rounded surface card with hairline separators inset past the tile.
    public struct CardGroup<Content: View>: View {
        private let content: Content

        public init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        public var body: some View {
            VStack(spacing: 0) {
                content
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.listCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.listCard, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.listCard, style: .continuous))
        }
    }

    private struct ListRowGallery: View {
        var body: some View {
            ScrollView {
                CardGroup {
                    ListRow(title: "Notifications", subtitle: "Messages, mentions and schedule", showsChevron: true) {
                        IconTile(systemImage: "bell", tone: .amber)
                    }
                    Divider().padding(.leading, ControlSize.fieldDividerInset)
                    ListRow(
                        title: "Maria-Fernanda Rodriguez-Villanueva",
                        subtitle: "Can you cover Friday? I have a family thing in the afternoon and need a swap.",
                        titleKind: .oneLineName
                    ) {
                        AvatarView(name: "Maria-Fernanda Rodriguez")
                    } trailing: {
                        CountBadge(count: 3)
                    }
                    Divider().padding(.leading, ControlSize.fieldDividerInset)
                    ListRow(title: "Appearance")
                }
                .padding(Spacing.medium)
            }
            .background(Palette.background)
        }
    }

    #Preview("Light") { ListRowGallery() }
    #Preview("Dark") { ListRowGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { ListRowGallery().dynamicTypeSize(.accessibility5) }
#endif
