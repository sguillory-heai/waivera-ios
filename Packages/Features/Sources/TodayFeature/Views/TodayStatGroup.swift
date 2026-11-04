#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One stat on the hero: its number, its label, what VoiceOver reads for it and, when the
    /// stat opens something, where (the schedule's day or week).
    struct TodayStat: Hashable {
        var value: String
        var label: String
        var spoken: String
        var opens: TodayDestination?

        init(_ parts: StatText, opens: TodayDestination? = nil) {
            value = parts.value
            label = parts.label
            spoken = parts.spoken
            self.opens = opens
        }
    }

    /// The hero's stats (Android `WaiveraStatGroup`): three equal glass tiles, or, when a tile's
    /// label would break inside a word or the text is extra large on a phone, one glass card with
    /// a row per stat. `compact` (a short window at regular text) sets the label beside the number.
    struct TodayStatGroup: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let stats: [TodayStat]
        var compact = false
        var onOpen: (TodayDestination) -> Void = { _ in }
        @State private var width: CGFloat = 0

        var body: some View {
            Group {
                if stacked {
                    card
                } else {
                    HStack(spacing: Spacing.small) {
                        ForEach(stats, id: \.self) { stat in
                            opening(stat, depth: .card) { tile(stat) }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .readWidth { width = $0 }
        }

        private var stacked: Bool {
            guard !compact else { return false }
            let widest =
                stats.map {
                    TodayMeasure.widestWord(in: $0.label, style: .statLabel, size: dynamicTypeSize)
                }.max() ?? 0
            let metrics = StatTileMetrics(
                gap: Double(Spacing.small),
                tilePadding: Double(Spacing.mediumSmall),
                stackMaxWidth: Double(ControlSize.statStackMaxWidth)
            )
            return WordFit.statsStack(
                widestLabelWord: Double(widest),
                width: Double(width),
                tiles: stats.count,
                extraLargeText: dynamicTypeSize.isExtraLargeText,
                metrics: metrics
            )
        }

        @ViewBuilder private func tile(_ stat: TodayStat) -> some View {
            Group {
                if compact {
                    HStack(spacing: Spacing.extraSmall + Spacing.xxSmall) {
                        StatNumber(value: stat.value)
                        label(stat).lineLimit(2)
                    }
                    .padding(.horizontal, Spacing.small + Spacing.xxSmall)
                    .padding(.vertical, Spacing.small)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        StatNumber(value: stat.value)
                        label(stat)
                    }
                    .padding(.horizontal, Spacing.mediumSmall)
                    .padding(.vertical, Spacing.mediumSmall - Spacing.hairline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glassTile()
            .contentShape(RoundedRectangle(cornerRadius: Radius.statTile, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(stat.spoken))
        }

        /// A stat that opens something is a button that presses at `depth`; others are plain.
        @ViewBuilder private func opening<Content: View>(
            _ stat: TodayStat,
            depth: PressDepth,
            @ViewBuilder content: () -> Content
        ) -> some View {
            if let destination = stat.opens {
                Button {
                    onOpen(destination)
                } label: {
                    content()
                }
                .buttonStyle(.press(depth))
                .frame(minHeight: ControlSize.minHitTarget)
            } else {
                content()
            }
        }

        private var card: some View {
            VStack(spacing: 0) {
                ForEach(stats, id: \.self) { stat in
                    opening(stat, depth: .row) {
                        HStack(spacing: Spacing.small) {
                            StatNumber(value: stat.value)
                            label(stat).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, Spacing.extraSmall + Spacing.xxSmall)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(stat.spoken))
                    }
                }
            }
            .padding(.horizontal, Spacing.mediumSmall)
            .padding(.vertical, Spacing.extraSmall)
            .glassTile()
        }

        private func label(_ stat: TodayStat) -> some View {
            Text(stat.label)
                .waiveraTextStyle(.statLabel)
                .foregroundStyle(HeroPalette.onHeaderSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A stat's number. A new value (the dash while loading giving way to "4") swaps in place on
    /// the shared swap motion instead of cutting (M3-04).
    private struct StatNumber: View {
        let value: String

        var body: some View {
            SwapView(value) { shown in
                Text(shown)
                    .waiveraTextStyle(.statNumeral)
                    .foregroundStyle(HeroPalette.onHeader)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    extension View {
        /// The faint glass of a hero stat tile and its hairline.
        fileprivate func glassTile() -> some View {
            background(HeroPalette.tile, in: RoundedRectangle(cornerRadius: Radius.statTile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.statTile, style: .continuous)
                        .strokeBorder(HeroPalette.tileBorder, lineWidth: Spacing.hairline)
                )
        }
    }
#endif
