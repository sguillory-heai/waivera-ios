#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A due group's title with its count chip (Android `GroupHeader`): rose for Overdue, the
    /// neutral chip for every other group. The count is the server's total for the group, not the
    /// rows shown, so it matches the line above the list.
    struct TaskGroupHeader: View {
        let section: TaskSection

        var body: some View {
            CountedSectionHeader(
                section.group.title,
                count: section.total,
                countLabel: TasksStrings.plural("tasks.group.count", section.total),
                tone: section.group == .overdue ? .attention : .info
            )
        }
    }
#endif
