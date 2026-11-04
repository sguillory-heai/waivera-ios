#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A due group's title with its count chip (Android `GroupHeader`): rose for Overdue, the
    /// neutral chip for every other group.
    struct TaskGroupHeader: View {
        let section: TaskSection

        var body: some View {
            CountedSectionHeader(
                section.group.title,
                count: section.rows.count,
                countLabel: TasksStrings.plural("tasks.group.count", section.rows.count),
                tone: section.group == .overdue ? .attention : .info
            )
        }
    }
#endif
