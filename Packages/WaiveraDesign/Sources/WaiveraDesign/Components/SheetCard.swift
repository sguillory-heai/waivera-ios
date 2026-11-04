#if canImport(UIKit)
    import SwiftUI

    public extension View {
        /// Android's sheet card (`WaiveraSheetCard`, `WaiveraCardGroup`): the surface with 20pt
        /// corners and the soft card lift. Shadows vanish on the dark background, so dark mode adds a
        /// hairline to keep the card's edge. Content is clipped to the corners.
        func sheetCard() -> some View {
            modifier(SheetCardModifier())
        }
    }

    private struct SheetCardModifier: ViewModifier {
        @Environment(\.colorScheme) private var colorScheme

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous)
            let lift = Elevation.shadow(for: Elevation.card)
            content
                .background(Palette.surface)
                .clipShape(shape)
                .overlay {
                    if colorScheme == .dark {
                        shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline)
                    }
                }
                .shadow(color: Palette.liftShadow, radius: lift.radius, x: 0, y: lift.y)
        }
    }

    /// Rows on one lifted card (Android `WaiveraCardGroup`), edge to edge inside it. Put an
    /// `InsetDivider` between rows. The caller insets the card by the gutter.
    public struct SheetCardGroup<Content: View>: View {
        private let content: Content

        public init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheetCard()
        }
    }

    /// A hairline between rows of a card, starting at `inset` and stopping 16pt short of the edge
    /// (Android `WaiveraInsetDivider`).
    public struct InsetDivider: View {
        private let inset: CGFloat

        public init(inset: CGFloat = Spacing.medium + ControlSize.fieldDividerInset) {
            self.inset = inset
        }

        public var body: some View {
            Rectangle()
                .fill(Palette.border)
                .frame(height: Spacing.hairline)
                .padding(.leading, inset)
                .padding(.trailing, Spacing.medium)
                .accessibilityHidden(true)
        }
    }

    /// A section title with an optional count chip after it (Android `WaiveraSectionHeader`):
    /// B's 17 / 600 title, then a rose count for something waiting on the person or a neutral
    /// chip for a plain total. The caller sets the padding.
    public struct CountedSectionHeader: View {
        private let title: String
        private let count: Int?
        private let countLabel: String?
        private let tone: CountTone

        public init(_ title: String, count: Int? = nil, countLabel: String? = nil, tone: CountTone = .attention) {
            self.title = title
            self.count = count
            self.countLabel = countLabel
            self.tone = tone
        }

        public var body: some View {
            HStack(spacing: Spacing.small) {
                Text(title)
                    .waiveraTextStyle(.titleMedium)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                if let count, count > 0 {
                    SectionCount(
                        text: BadgeFormatter.text(for: count) ?? String(count),
                        accessibilityText: countLabel ?? String(count),
                        tone: tone
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A section's count: 24pt tall with 8pt corners, solid rose with white for attention, the
    /// neutral chip for a plain total (Android `WaiveraSectionCount`).
    public struct SectionCount: View {
        private let text: String
        private let accessibilityText: String
        private let tone: CountTone

        public init(text: String, accessibilityText: String, tone: CountTone = .attention) {
            self.text = text
            self.accessibilityText = accessibilityText
            self.tone = tone
        }

        public var body: some View {
            Text(text)
                .waiveraTextStyle(.sectionCount)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(tone.inkColor)
                .padding(.horizontal, Spacing.small)
                .frame(minWidth: ControlSize.countBadgeHeight, minHeight: ControlSize.countBadgeHeight)
                .background(tone.fillColor, in: RoundedRectangle(cornerRadius: Radius.countBadge, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityText))
        }
    }

    private struct SheetCardGallery: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                CountedSectionHeader("Overdue", count: 1)
                CountedSectionHeader("This week", count: 12, tone: .info)
                SheetCardGroup {
                    Text(verbatim: "First row").padding(Spacing.medium)
                    InsetDivider(inset: Spacing.medium)
                    Text(verbatim: "Second row").padding(Spacing.medium)
                }
            }
            .padding(Spacing.gutter)
            .background(Palette.background)
        }
    }

    #Preview("Light") { SheetCardGallery() }
    #Preview("Dark") { SheetCardGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { SheetCardGallery().dynamicTypeSize(.accessibility5) }
#endif
