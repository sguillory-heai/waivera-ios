#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// At a glance (Android `TaskCard`): the due date as a tile, the title, who it is about, one
    /// line of facts (lateness in the attention colour or the delay in the link colour, then the
    /// key, then another owner on its own line) and at most one badge.
    struct TaskCard: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let row: TaskRow
        let onOpen: () -> Void

        var body: some View {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                    DateTile(month: row.tileMonth, day: row.tileDay, tone: tileTone)
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(row.title)
                            .waiveraTextStyle(.titleSmall)
                            .foregroundStyle(Palette.text)
                            .lineLimit(large ? 4 : 2)
                        if let about = row.about {
                            Text(about)
                                .waiveraTextStyle(.bodySmall)
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                        }
                        Text(metaLine)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                        if let badge {
                            StatusBadge(badge.title, tone: badge.tone)
                                .padding(.top, Spacing.xxSmall)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Room for the chevron, which centres on the whole card in the overlay below.
                    Color.clear.frame(width: ControlSize.iconSmall, height: Spacing.hairline)
                }
                .overlay(alignment: .trailing) { TaskChevron() }
                .padding(Spacing.mediumSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sheetCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(row.accessibilityLabel + (badge.map { ", \($0.title)" } ?? "")))
            .accessibilityHint(Text(TasksStrings.text("tasks.openTask")))
            .accessibilityAddTraits(.isButton)
        }

        private var large: Bool { dynamicTypeSize >= .accessibility1 }

        /// Really overdue turns the tile red; a delay keeps it brand violet (the web's purple ink).
        private var tileTone: TileTone {
            row.daysLate != nil && !row.delayed ? .danger : .brand
        }

        /// Lateness or the delay, the key, then another owner on its own line. At large text each
        /// fact stacks.
        private var metaLine: AttributedString {
            let separator = large ? "\n" : "\u{00A0}· "
            var text = AttributedString()
            if let daysLate = row.daysLate, !row.delayed {
                var late = AttributedString(TasksStrings.plural("tasks.row.daysLate", daysLate))
                late.foregroundColor = Palette.dangerText
                text += late + AttributedString(separator)
            }
            if row.delayed {
                let words = row.delayedThrough
                    .map { TasksStrings.format("tasks.row.delayedThrough", Self.unbroken($0)) }
                    ?? TasksStrings.text("tasks.row.delayed")
                var delay = AttributedString(words)
                delay.foregroundColor = Palette.link
                text += delay + AttributedString(separator)
            }
            text += AttributedString(row.key)
            if let assignee = row.assignee {
                text += AttributedString("\n" + TasksStrings.format("tasks.row.assignedTo", Self.unbroken(assignee)))
            }
            return text
        }

        /// Keeps "Nov 20" or a name on one line.
        private static func unbroken(_ text: String) -> String {
            text.replacingOccurrences(of: " ", with: "\u{00A0}")
        }

        private var badge: (title: String, tone: BadgeTone)? {
            switch row.flag {
            case .closureRequested: (TasksStrings.text("tasks.flag.closure"), .warning)
            case .inProgress: (TasksStrings.text("tasks.state.inProgress"), .accent)
            case .inReview: (TasksStrings.text("tasks.state.inReview"), .warning)
            case nil: nil
            }
        }
    }

    /// The trailing chevron on a task or request card, centred on the card.
    struct TaskChevron: View {
        var systemImage = "chevron.right"

        var body: some View {
            Image(systemName: systemImage)
                .font(.system(size: ControlSize.iconSmall, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: ControlSize.iconSmall)
                .accessibilityHidden(true)
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
