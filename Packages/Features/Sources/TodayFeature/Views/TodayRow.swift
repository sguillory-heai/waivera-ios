#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraDesign

    /// The shared Today card: a lifted surface card on the sheet with an optional kicker ("Not
    /// sent", "Mention · 5m"), a headline that wraps (three lines at most), supporting text, a
    /// leading tile and a trailing slot, ending in a chevron. The tile centres on a standard card
    /// and pins level with the first line once content makes the card taller (v7 item 1).
    /// VoiceOver reads the tappable part as one element; `quote` is what someone said, on its own
    /// line behind a rule; `below` holds separate actions (Decline and Accept) outside the tap.
    struct TodayRow<Leading: View, Trailing: View, Below: View>: View {
        var eyebrow: String?
        var eyebrowTint: Color = Palette.textSecondary
        let headline: String
        var supporting: String?
        var quote: String?
        var quoteRuleTint: Color = Palette.accent
        var emphasized = false
        var showsChevron = true
        let accessibilityText: String
        let accessibilityHintText: String
        let action: () -> Void
        @ViewBuilder let leading: () -> Leading
        @ViewBuilder let trailing: () -> Trailing
        @ViewBuilder let below: () -> Below

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: action) {
                    TodayPinnedRow {
                        leading()
                    } content: {
                        HStack(spacing: TodayCard.gap) {
                            content
                            trailing()
                            if showsChevron {
                                Image(systemName: "chevron.right")
                                    .font(WaiveraFont.captionEmphasis)
                                    .foregroundStyle(Palette.textSecondary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(TodayCard.padding)
                    .frame(maxWidth: .infinity, minHeight: ControlSize.listRowMinHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.card))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityText))
                .accessibilityHint(Text(accessibilityHintText))
                .accessibilityAddTraits(.isButton)
                below()
                    .padding(.leading, TodayCard.padding + ControlSize.cardTile + TodayCard.gap)
                    .padding(.trailing, TodayCard.padding)
            }
            .todayCard(radius: Radius.sheetCard)
            .todayCardSpacing()
        }

        private var content: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let eyebrow {
                    Text(eyebrow)
                        .waiveraTextStyle(.kicker)
                        .foregroundStyle(eyebrowTint)
                        .padding(.bottom, Spacing.xxSmall)
                }
                Text(headline)
                    .waiveraTextStyle(.titleSmall)
                    .fontWeight(emphasized ? .bold : .semibold)
                    .foregroundStyle(Palette.text)
                    .lineLimit(TodayCard.headlineLines)
                if let quote {
                    HStack(spacing: Spacing.small) {
                        Capsule()
                            .fill(quoteRuleTint)
                            .frame(width: ControlSize.quoteRule)
                        Text(quote)
                            .waiveraTextStyle(.bodyMedium)
                            .foregroundStyle(Palette.text)
                            .lineLimit(TodayCard.quoteLines)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.extraSmall)
                }
                if let supporting, !supporting.isEmpty {
                    Text(supporting)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(TodayCard.supportingLines)
                        .padding(.top, Spacing.xxSmall)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    extension TodayRow where Trailing == EmptyView, Below == EmptyView {
        init(
            eyebrow: String? = nil,
            eyebrowTint: Color = Palette.textSecondary,
            headline: String,
            supporting: String? = nil,
            quote: String? = nil,
            quoteRuleTint: Color = Palette.accent,
            emphasized: Bool = false,
            showsChevron: Bool = true,
            accessibilityText: String,
            accessibilityHintText: String,
            action: @escaping () -> Void,
            @ViewBuilder leading: @escaping () -> Leading
        ) {
            self.init(
                eyebrow: eyebrow,
                eyebrowTint: eyebrowTint,
                headline: headline,
                supporting: supporting,
                quote: quote,
                quoteRuleTint: quoteRuleTint,
                emphasized: emphasized,
                showsChevron: showsChevron,
                accessibilityText: accessibilityText,
                accessibilityHintText: accessibilityHintText,
                action: action,
                leading: leading,
                trailing: { EmptyView() },
                below: { EmptyView() }
            )
        }
    }

    extension TodayRow where Below == EmptyView {
        init(
            eyebrow: String? = nil,
            eyebrowTint: Color = Palette.textSecondary,
            headline: String,
            supporting: String? = nil,
            emphasized: Bool = false,
            accessibilityText: String,
            accessibilityHintText: String,
            action: @escaping () -> Void,
            @ViewBuilder leading: @escaping () -> Leading,
            @ViewBuilder trailing: @escaping () -> Trailing
        ) {
            self.init(
                eyebrow: eyebrow,
                eyebrowTint: eyebrowTint,
                headline: headline,
                supporting: supporting,
                emphasized: emphasized,
                accessibilityText: accessibilityText,
                accessibilityHintText: accessibilityHintText,
                action: action,
                leading: leading,
                trailing: trailing,
                below: { EmptyView() }
            )
        }
    }

    /// A leading tile or avatar beside a card's content, centred on a standard card and pinned
    /// level with the first line once the content is taller than a two-line row (v7 item 1).
    struct TodayPinnedRow<Leading: View, Content: View>: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private let leading: Leading
        private let content: Content

        init(@ViewBuilder leading: () -> Leading, @ViewBuilder content: () -> Content) {
            self.leading = leading()
            self.content = content()
        }

        var body: some View {
            LeadingPinLayout(spacing: TodayCard.gap, standardHeight: TodayCard.standardHeight(dynamicTypeSize)) {
                leading
                content.leadingPinContent()
            }
        }
    }

    extension EnvironmentValues {
        /// A short window (under 700pt): cards sit 8pt apart instead of 10 so two Needs you cards
        /// show under the hero (UI10-01).
        @Entry var todayCompactWindow = false
    }

    private struct TodayCardSpacing: ViewModifier {
        @Environment(\.todayCompactWindow) private var compact

        func body(content: Content) -> some View {
            content
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, compact ? Spacing.extraSmall : Spacing.extraSmall + Spacing.hairline)
        }
    }

    extension View {
        /// The gutter beside a sheet card and the gap between cards.
        func todayCardSpacing() -> some View { modifier(TodayCardSpacing()) }
    }

    /// A Today card's measures: 14pt inside, 14pt between the tile and the text.
    enum TodayCard {
        static let padding = Spacing.mediumSmall + Spacing.xxSmall
        static let gap = Spacing.mediumSmall + Spacing.xxSmall
        static let headlineLines = 3
        static let supportingLines = 2
        static let quoteLines = 2

        /// A title line, the 2pt gap and a subtitle line plus half a line of slack, at this size.
        static func standardHeight(_ size: DynamicTypeSize) -> CGFloat {
            let traits = UITraitCollection(preferredContentSizeCategory: size.uiContentSizeCategory)
            return CGFloat(
                LeadingTileAlignment.twoLineRowContentHeight(
                    titleLine: Double(TextStyleToken.titleSmall.scaledLineHeight(compatibleWith: traits)),
                    gap: Double(Spacing.xxSmall),
                    subtitleLine: Double(TextStyleToken.bodySmall.scaledLineHeight(compatibleWith: traits))
                )
            )
        }
    }

    /// The card's leading tile: 44pt with a 22pt glyph.
    struct TodayTile: View {
        let systemImage: String
        let tone: TileTone

        var body: some View {
            IconTile(
                systemImage: systemImage,
                tone: tone,
                size: ControlSize.cardTile,
                glyphSize: ControlSize.cardTileGlyph
            )
        }
    }

    /// A sheet section header: the title on one line (it never breaks mid-word), an optional
    /// count and trailing actions with what width is left.
    struct TodaySectionHeader<Trailing: View>: View {
        let title: String
        var first = false
        /// How many items the section holds, in a badge after the title.
        var count: Int?
        @ViewBuilder let trailing: () -> Trailing

        var body: some View {
            HStack(spacing: Spacing.small) {
                Text(title)
                    .waiveraTextStyle(.titleMedium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                if let count, count > 0 {
                    StatusBadge(String(count), tone: .accent)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(TodayStrings.plural("today.sectionCount", count)))
                }
                Spacer(minLength: Spacing.small)
                trailing()
            }
            .frame(minHeight: ControlSize.minHitTarget)
            .padding(.leading, Spacing.gutter + Spacing.extraSmall)
            .padding(.trailing, Spacing.small)
            .padding(.top, first ? Spacing.none : Spacing.extraLarge)
            .padding(.bottom, first ? Spacing.small : Spacing.mediumSmall)
        }
    }

    extension TodaySectionHeader where Trailing == EmptyView {
        init(title: String, first: Bool = false) {
            self.init(title: title, first: first, trailing: { EmptyView() })
        }
    }

    /// A text action in a section header ("Show all", "See schedule"), with a 44pt hit target.
    struct TodayTextButton: View {
        let title: String
        var systemImage: String?
        var hint: String?
        var isLoading = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    label.opacity(isLoading ? 0 : 1)
                    if isLoading {
                        BusyIndicator(size: ControlSize.progressSmall, lineWidth: ControlSize.progressStroke)
                    }
                }
                .waiveraTextStyle(.sectionAction)
                .foregroundStyle(Palette.link)
                .padding(.horizontal, Spacing.small)
                .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.compact))
            .disabled(isLoading)
            .accessibilityHint(hint.map { Text($0) } ?? Text(verbatim: ""))
        }

        @ViewBuilder private var label: some View {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }
#endif
