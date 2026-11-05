#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Nothing to decide: the same reward art as an empty inbox, and a small way to your own.
    struct RequestsCaughtUp: View {
        let onOpenMine: () -> Void

        var body: some View {
            VStack(spacing: Spacing.small) {
                EmptyStateView(
                    illustration: .caughtUp,
                    title: TasksStrings.text("tasks.requests.caughtUpTitle"),
                    message: TasksStrings.text("tasks.requests.caughtUpMessage")
                )
                WaiveraButton(
                    TasksStrings.text("tasks.requests.viewMine"),
                    variant: .tonal,
                    size: .compact,
                    action: onOpenMine
                )
                .accessibilityIdentifier("requests.viewMine")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.large)
            .padding(.horizontal, Spacing.gutter)
        }
    }

    /// One quiet row after the waiting cards: the person's own requests, and how many still wait.
    struct RequestsMineRow: View {
        let mine: Loadable<[RequestItem]>
        let onOpen: () -> Void

        var body: some View {
            Button(action: onOpen) {
                HStack(spacing: Spacing.mediumSmall) {
                    IconTile(systemImage: "calendar", tone: .brand)
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(TasksStrings.text("tasks.requests.mine"))
                            .waiveraTextStyle(.titleSmall)
                            .foregroundStyle(Palette.text)
                        if let summary {
                            Text(summary)
                                .waiveraTextStyle(.bodySmall)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TaskChevron()
                }
                .padding(Spacing.mediumSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Palette.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.card))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("requests.mineRow")
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.medium)
        }

        private var summary: String? {
            guard let rows = mine.value else { return nil }
            return Self.summary(rows.map(\.request.status))
        }

        /// "1 pending · 3 in all", "3 in all", or "None yet".
        static func summary(_ statuses: [RequestStatus]) -> String {
            let pending = statuses.filter { $0 == .pending }.count
            let total = TasksStrings.plural("tasks.requests.mineTotal", statuses.count)
            if statuses.isEmpty { return TasksStrings.text("tasks.requests.mineNone") }
            if pending == 0 { return total }
            return TasksStrings.format(
                "tasks.requests.mineSummary",
                TasksStrings.plural("tasks.requests.minePending", pending),
                total
            )
        }
    }
#endif
