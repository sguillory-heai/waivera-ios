#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A group's title and how many tasks it holds.
    struct TaskGroupHeader: View {
        let section: TaskSection

        var body: some View {
            HStack {
                Text(section.group.title)
                    .waiveraTextStyle(.labelLarge, weight: .bold)
                    .foregroundStyle(section.group == .overdue ? Palette.dangerText : Palette.text)
                Spacer()
                Text(TasksStrings.plural("tasks.group.count", section.rows.count))
                    .waiveraTextStyle(.labelMedium)
                    .foregroundStyle(Palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }
#endif
