#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraDesign

    /// "Your day" on Today's sheet: how many events and how much time today holds, the day as a
    /// track (8 AM to 6 PM, wider when the day needs it) with a now-line, and today's next timed
    /// event under it. Times are the employee's zone, worked out in the model. The track is one
    /// VoiceOver item; the blocks are colour only, so the summary and the next row carry the times.
    struct YourDayCard: View {
        let day: DayTimeline
        let next: NextUpItem?
        let onOpenEvent: (String) -> Void

        var body: some View {
            let formatter = TodayFormatting.shared
            let summary = TodayStrings.daySummary(day)
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    Text(TodayStrings.text("today.day.title"))
                        .waiveraTextStyle(.panelTitle)
                        .foregroundStyle(Palette.text)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                    Text(summary)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DayTrack(day: day)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        Text(
                            TodayStrings.format(
                                "today.day.track",
                                summary,
                                formatter.time(day.windowStart),
                                formatter.time(day.windowEnd)
                            )
                        )
                    )
                AxisLabels(day: day)
                if let next, next.start != nil {
                    DayNextRow(item: next) { onOpenEvent(next.eventId) }
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.mediumSmall + Spacing.xxSmall)
            .todayCard(radius: Radius.timelinePanel)
        }
    }

    /// The track: hour ticks, a block per event in the three timeline colours, and the pink
    /// now-line with its dot, drawn over the blocks.
    private struct DayTrack: View {
        let day: DayTimeline

        var body: some View {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let inset = ControlSize.timelineBlockInset
                ZStack(alignment: .topLeading) {
                    Palette.surfaceMuted
                    ForEach(Array(day.ticks.enumerated()), id: \.offset) { _, tick in
                        Rectangle()
                            .fill(Palette.border)
                            .frame(width: Spacing.hairline, height: height)
                            .offset(x: width * CGFloat(tick))
                    }
                    ForEach(day.blocks, id: \.eventId) { block in
                        let left = width * CGFloat(block.start)
                        let right = width * CGFloat(block.end)
                        RoundedRectangle(cornerRadius: inset + Spacing.hairline, style: .continuous)
                            .fill(DayTrack.tone(block.tone))
                            .frame(width: max(inset, right - left), height: max(0, height - inset * 2))
                            .offset(x: left, y: inset)
                    }
                    if let now = day.now {
                        let x = width * CGFloat(now)
                        Rectangle()
                            .fill(DayTrack.nowColor)
                            .frame(width: ControlSize.timelineNowLine, height: height)
                            .offset(x: x - ControlSize.timelineNowLine / 2)
                        Circle()
                            .fill(DayTrack.nowColor)
                            .frame(width: ControlSize.timelineNowDot, height: ControlSize.timelineNowDot)
                            .offset(x: x - ControlSize.timelineNowDot / 2)
                    }
                }
            }
            .frame(height: ControlSize.timelineTrack)
            .clipShape(RoundedRectangle(cornerRadius: Radius.timelineTrack, style: .continuous))
        }

        static let nowColor = Color(rgb: RGBColor(hex: BrandPalette.brandPink))

        static func tone(_ index: Int) -> Color {
            let tones = [BrandPalette.timelineTeal, BrandPalette.timelineViolet, BrandPalette.timelineGold]
            return Color(rgb: RGBColor(hex: tones[index % tones.count]))
        }
    }

    /// Hour labels centred on their positions, kept inside the track; labels that would collide
    /// at large text are dropped, never overlapped. "8 AM" at the ends and at noon, the bare hour
    /// between ("10", "2").
    private struct AxisLabels: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let day: DayTimeline
        @State private var width: CGFloat = 0

        var body: some View {
            let texts = day.labels.enumerated().map { index, label in
                TodayFormatting.shared.hour(
                    label.time,
                    withPeriod: index == 0 || index == day.labels.count - 1 || label.time.hour == 12
                )
            }
            let widths = texts.map { TodayMeasure.width(of: $0, style: .axisLabel, size: dynamicTypeSize) }
            let offsets = AxisLabelPlacement.place(
                centers: day.labels.map(\.position),
                widths: widths.map(Double.init),
                total: Double(width),
                gap: Double(Spacing.small)
            )
            ZStack(alignment: .topLeading) {
                Text(verbatim: " ").waiveraTextStyle(.axisLabel).hidden()
                ForEach(Array(texts.enumerated()), id: \.offset) { index, text in
                    if width > 0, let x = offsets[index] {
                        Text(text)
                            .waiveraTextStyle(.axisLabel)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                            .offset(x: CGFloat(x))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .readWidth { width = $0 }
            .accessibilityHidden(true)
        }
    }

    /// Today's next timed event under the track: the clock ("11:00 AM") with the countdown chip
    /// under it while it is close, a teal dot, then the title with "Until 12:00 PM · place". The
    /// chip sits under the clock so the title keeps the row's width on a small phone.
    private struct DayNextRow: View {
        let item: NextUpItem
        let onOpen: () -> Void

        var body: some View {
            let formatter = TodayFormatting.shared
            let title = item.title ?? TodayStrings.text("today.invitation.untitled")
            let place = item.location ?? (item.isOnline ? TodayStrings.text("today.online") : nil)
            let until = item.end.map { TodayStrings.format("today.until", formatter.time($0)) }
            let meta = until.map { TodayStrings.joined($0, place) } ?? place
            let upcoming = formatter.upcoming(item.time)
            let start = item.start.map(formatter.time) ?? upcoming
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Palette.border)
                    .frame(height: Spacing.hairline)
                Button(action: onOpen) {
                    HStack(spacing: Spacing.mediumSmall) {
                        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                            Text(start)
                                .waiveraTextStyle(.clockTime)
                                .foregroundStyle(Palette.text)
                                .fixedSize()
                            if item.isCountdown { CountdownChip(text: upcoming) }
                        }
                        Circle()
                            .fill(TileTone.teal.contentColor)
                            .frame(width: ControlSize.timelineNowDot, height: ControlSize.timelineNowDot)
                            .padding(Spacing.extraSmall)
                            .background(TileTone.teal.containerColor, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title)
                                .waiveraTextStyle(.titleSmall)
                                .foregroundStyle(Palette.text)
                                .lineLimit(2)
                            if let meta {
                                Text(meta)
                                    .waiveraTextStyle(.bodySmall)
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, Spacing.mediumSmall)
                    .padding(.bottom, Spacing.xxSmall)
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text(TodayStrings.joined(TodayStrings.joined(TodayStrings.joined(start, title), meta), upcoming))
                )
                .accessibilityHint(Text(TodayStrings.text("today.hint.openEvent")))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    extension TodayMeasure {
        /// The width of `text` set on one line in `style`.
        static func width(of text: String, style: TextStyleToken, size: DynamicTypeSize) -> CGFloat {
            let traits = UITraitCollection(preferredContentSizeCategory: size.uiContentSizeCategory)
            let font = style.uiFont(compatibleWith: traits)
            let measured = (text as NSString).size(withAttributes: [.font: font]).width
            return ceil(measured + CGFloat(style.spec.tracking) * CGFloat(max(0, text.count - 1)))
        }
    }

    extension View {
        /// A lifted card on the sheet: the surface, rounded, with the faint card shadow.
        func todayCard(radius: CGFloat) -> some View {
            background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(
                    color: Palette.buttonRaise,
                    radius: Elevation.shadow(for: Elevation.card).radius,
                    x: 0,
                    y: Elevation.shadow(for: Elevation.card).y
                )
        }
    }

    #if DEBUG
        #Preview("Light") {
            YourDayCard(day: TodayPreviewStates.day(), next: TodayPreviewStates.populated().nextUp.items[1]) { _ in }
                .padding(Spacing.medium)
                .background(Palette.background)
        }

        #Preview("Dark") {
            YourDayCard(day: TodayPreviewStates.day(), next: TodayPreviewStates.populated().nextUp.items[1]) { _ in }
                .padding(Spacing.medium)
                .background(Palette.background)
                .preferredColorScheme(.dark)
        }

        #Preview("AX5") {
            YourDayCard(day: TodayPreviewStates.day(), next: TodayPreviewStates.populated().nextUp.items[1]) { _ in }
                .padding(Spacing.medium)
                .background(Palette.background)
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
