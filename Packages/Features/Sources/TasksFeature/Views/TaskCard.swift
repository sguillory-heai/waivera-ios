#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One task card: a date tile, the title and number, who it is about, the due line and at
    /// most one badge. A delay reads "Delayed through …" in place of late.
    struct TaskCard: View {
        let row: TaskRow
        let onOpen: () -> Void

        var body: some View {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                    DateTile(month: row.tileMonth, day: row.tileDay, tone: tileTone)
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(row.title)
                            .waiveraTextStyle(.titleSmall, weight: .semibold)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                        Text([row.key, row.about].compactMap(\.self).joined(separator: " · "))
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                        Text(row.dueLine)
                            .waiveraTextStyle(.labelMedium, weight: .semibold)
                            .foregroundStyle(dueColor)
                        if let assignee = row.assignee {
                            Text(TasksStrings.format("tasks.row.assignedTo", assignee))
                                .waiveraTextStyle(.bodySmall)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                        }
                        if let badge {
                            StatusBadge(badge.title, tone: badge.tone)
                                .padding(.top, Spacing.extraSmall)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, Spacing.extraSmall)
                        .accessibilityHidden(true)
                }
                .padding(Spacing.medium)
                .frame(minHeight: ControlSize.listRowMinHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.listCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.listCard).stroke(Palette.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(row.accessibilityLabel + (badge.map { ", \($0.title)" } ?? "")))
            .accessibilityHint(Text(TasksStrings.text("tasks.openTask")))
            .accessibilityAddTraits(.isButton)
        }

        private var tileTone: TileTone {
            if row.delayed { return .amber }
            if row.daysLate != nil { return .danger }
            return .brand
        }

        private var dueColor: Color {
            if row.delayed { return Palette.warningText }
            if row.daysLate != nil { return Palette.dangerText }
            return Palette.textSecondary
        }

        private var badge: (title: String, tone: BadgeTone)? {
            switch row.flag {
            case .closureRequested: (TasksStrings.text("tasks.flag.closure"), .warning)
            case .inProgress: (TasksStrings.text("tasks.state.inProgress"), .accent)
            case .inReview: (TasksStrings.text("tasks.state.inReview"), .warning)
            case nil: row.delayed ? (TasksStrings.text("tasks.row.delayed"), .warning) : nil
            }
        }
    }

    #if DEBUG
        private let previewRows = [
            TaskRow(
                id: 1,
                key: "HEA-1042",
                title: "Intake review",
                about: "Jordan Lee",
                due: .wasOn("Nov 2"),
                state: .inProgress,
                tileMonth: "Nov",
                tileDay: "2",
                daysLate: 2,
                delayed: false,
                assignee: nil,
                flag: .inProgress,
                group: .overdue
            ),
            TaskRow(
                id: 2,
                key: "HEA-1047",
                title: "Quarterly visit",
                about: "Sam Ortiz",
                due: .wasOn("Oct 30"),
                state: .notStarted,
                tileMonth: "Oct",
                tileDay: "30",
                delayed: true,
                delayedThrough: "Nov 10",
                assignee: "Dana Cole",
                group: .delayed
            ),
        ]

        #Preview("Cards") {
            VStack(spacing: Spacing.small) {
                ForEach(previewRows) { TaskCard(row: $0, onOpen: {}) }
            }
            .padding()
            .background(Palette.background)
        }
        #Preview("Cards dark") {
            VStack(spacing: Spacing.small) { ForEach(previewRows) { TaskCard(row: $0, onOpen: {}) } }
                .padding().background(Palette.background).preferredColorScheme(.dark)
        }
        #Preview("Cards AX5") {
            ScrollView { VStack(spacing: Spacing.small) { ForEach(previewRows) { TaskCard(row: $0, onOpen: {}) } } }
                .padding().background(Palette.background).dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
