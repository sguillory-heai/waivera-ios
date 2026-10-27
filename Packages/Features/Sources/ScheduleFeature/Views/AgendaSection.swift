#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The selected day's agenda in its fixed order, or its loading, error and empty states.
    struct AgendaSection: View {
        let heading: String
        let agenda: AgendaState
        let onOpenEvent: (String) -> Void
        let onRetry: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                Text(heading)
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                LoadingContent(isLoading: agenda == .loading) {
                    content
                } skeleton: {
                    AgendaSkeleton()
                }
            }
        }

        @ViewBuilder private var content: some View {
            switch agenda {
            case .loading:
                EmptyView()
            case .error(let error):
                EmptyStateView.error(
                    title: ScheduleStrings.text("schedule.error.title"),
                    message: error.userMessage,
                    onRetry: onRetry
                )
            case .empty:
                EmptyStateView(
                    systemImage: "calendar",
                    title: ScheduleStrings.text("schedule.empty.title"),
                    message: ScheduleStrings.text("schedule.empty.message")
                )
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            case .content(let rows):
                VStack(spacing: Spacing.small) {
                    ForEach(rows) { row in
                        AgendaCard(row: row, onOpenEvent: onOpenEvent)
                    }
                }
            }
        }
    }
#endif
