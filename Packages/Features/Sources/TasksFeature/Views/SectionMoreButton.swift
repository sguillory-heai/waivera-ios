#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Under a section that holds more than its first rows (Android `SectionMoreButton`): "Show 42
    /// more" opens the next batch in place, and once it is all open "Show fewer" folds it back.
    struct SectionMoreButton: View {
        let group: DueGroup
        let more: SectionMore
        let onShowMore: () -> Void
        let onShowFewer: () -> Void

        var body: some View {
            WaiveraButton(
                title,
                variant: .tonal,
                systemImage: systemImage,
                isLoading: isLoading,
                loadingTitle: TasksStrings.text("tasks.loadingMore"),
                fillsWidth: true,
                action: isFewer ? onShowFewer : onShowMore
            )
            .accessibilityLabel(Text(isLoading ? TasksStrings.text("tasks.loadingMore") : description))
        }

        private var isFewer: Bool { more == .showFewer }

        private var isLoading: Bool {
            if case .showMore(_, true, _) = more { return true }
            return false
        }

        private var title: String {
            switch more {
            case .showMore(_, _, true): TasksStrings.text("tasks.section.moreFailed")
            case .showMore(let hidden, _, _): TasksStrings.plural("tasks.section.more", hidden)
            case .showFewer: TasksStrings.text("tasks.section.fewer")
            }
        }

        private var description: String {
            switch more {
            case .showMore(_, _, true): TasksStrings.format("tasks.section.moreFailed.description", group.title)
            case .showMore(let hidden, _, _): TasksStrings.plural("tasks.section.more.description", hidden, group.title)
            case .showFewer: TasksStrings.format("tasks.section.fewer.description", group.title)
            }
        }

        private var systemImage: String {
            switch more {
            case .showMore(_, _, true): "arrow.clockwise"
            case .showMore: "chevron.down"
            case .showFewer: "chevron.up"
            }
        }
    }

    #Preview {
        VStack(spacing: Spacing.small) {
            SectionMoreButton(group: .overdue, more: .showMore(hidden: 42), onShowMore: {}, onShowFewer: {})
            SectionMoreButton(group: .delayed, more: .showMore(hidden: 13, loading: true)) {} onShowFewer: {}
            SectionMoreButton(group: .thisWeek, more: .showMore(hidden: 8, failed: true)) {} onShowFewer: {}
            SectionMoreButton(group: .later, more: .showFewer, onShowMore: {}, onShowFewer: {})
        }
        .padding()
    }
#endif
