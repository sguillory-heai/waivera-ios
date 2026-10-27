#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One of the next three schedule items: relative time first ("in 25 min"), then the title,
    /// the clock range and the place. Soon items are tinted, with "Happening now" spoken too.
    struct NextUpRow: View {
        let item: NextUpItem
        let formatter: TodayFormatter
        let onOpen: () -> Void

        var body: some View {
            let title = item.title ?? TodayStrings.text("today.invitation.untitled")
            let time = formatter.upcoming(item.time)
            let place = item.location ?? (item.isOnline ? TodayStrings.text("today.online") : nil)
            let supporting = formatter.range(item).map { TodayStrings.joined($0, place) } ?? place
            TodayRow(
                eyebrow: time,
                eyebrowTint: item.isSoon ? Palette.accent : Palette.textSecondary,
                headline: title,
                supporting: supporting,
                emphasized: item.isHappeningNow,
                showsChevron: true,
                accessibilityText: TodayStrings.spoken(
                    time,
                    title,
                    supporting,
                    item.isHappeningNow ? TodayStrings.text("today.nextUp.happeningNow") : nil
                ),
                accessibilityHintText: TodayStrings.text("today.hint.openEvent"),
                action: onOpen,
                leading: {
                    IconTile(
                        systemImage: item.isAllDay ? "sun.max" : "clock",
                        tint: item.isSoon ? Palette.accent : Palette.textSecondary
                    )
                }
            )
        }
    }

    /// A birthday or work anniversary today. The avatar ring and the sentence carry the same meaning.
    struct CelebrationRow: View {
        let item: CelebrationItem
        let onOpen: () -> Void

        var body: some View {
            let sentence = TodayStrings.celebration(item)
            let name = item.name ?? TodayStrings.text("today.celebration.nameFallback")
            TodayRow(
                headline: sentence,
                accessibilityText: sentence,
                accessibilityHintText: TodayStrings.text("today.hint.openSchedule"),
                action: onOpen,
                leading: {
                    AvatarView(name: name, size: ControlSize.iconTile, rounded: true, milestoneLabel: sentence)
                }
            )
        }
    }

    extension NextUpItem {
        /// All-day items have no clock range.
        var isAllDay: Bool { start == nil }
    }
#endif
