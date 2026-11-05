#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A participant profile change (sprout_web `renderChangeDiff`): changed fields first, each
    /// previous beside requested, and the unchanged ones folded into one row.
    struct ReviewProfile: View {
        let changed: [ProfileRow]
        let unchanged: [ProfileRow]

        @State private var showsUnchanged = false

        var body: some View {
            HStack(spacing: Spacing.small) {
                if !changed.isEmpty {
                    StatusBadge(TasksStrings.plural("tasks.review.changed", changed.count), tone: .warning)
                }
                if !unchanged.isEmpty {
                    StatusBadge(TasksStrings.plural("tasks.review.unchanged", unchanged.count), tone: .neutral)
                }
            }
            if changed.isEmpty && unchanged.isEmpty {
                SheetCardGroup {
                    FactRow(systemImage: "person", label: TasksStrings.text("tasks.kind.profile")) {
                        FactValue(text: TasksStrings.text("tasks.review.profileEmpty"))
                    }
                }
            }
            if !changed.isEmpty {
                SheetCardGroup {
                    ForEach(Array(changed.enumerated()), id: \.element.field) { index, row in
                        if index > 0 { InsetDivider(inset: Spacing.medium) }
                        ProfileCompare(row: row)
                    }
                }
            }
            if !unchanged.isEmpty {
                SheetCardGroup {
                    Button {
                        showsUnchanged.toggle()
                    } label: {
                        FactRow(
                            systemImage: "checkmark",
                            label: TasksStrings.text("tasks.review.unchangedFields"),
                            tone: .teal
                        ) {
                            if showsUnchanged {
                                ForEach(unchanged, id: \.field) { row in
                                    FactNote(
                                        text: TasksStrings.format(
                                            "tasks.review.fieldValue",
                                            ProfileLabels.label(row.field),
                                            row.requested ?? TasksStrings.text("tasks.review.none")
                                        )
                                    )
                                }
                            } else {
                                FactValue(text: unchanged.map { ProfileLabels.label($0.field) }.joined(separator: ", "))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.card))
                    .accessibilityValue(
                        Text(TasksStrings.text(showsUnchanged ? "tasks.review.expanded" : "tasks.review.collapsed"))
                    )
                }
            }
        }
    }

    /// Previous beside requested; stacked when either is long or the text is large, so nothing is cut.
    struct ProfileCompare: View {
        private static let sideBySideCharacters = 12

        let row: ProfileRow
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            let none = TasksStrings.text("tasks.review.none")
            let previous = row.previous ?? none
            let requested = row.requested ?? none
            let stacked =
                dynamicTypeSize >= .accessibility1 || previous.count > Self.sideBySideCharacters
                || requested.count > Self.sideBySideCharacters
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(ProfileLabels.label(row.field))
                    .waiveraTextStyle(.fieldLabel)
                    .foregroundStyle(Palette.textSecondary)
                if stacked {
                    box(TasksStrings.text("tasks.review.previous"), previous, struck: true)
                    box(TasksStrings.text("tasks.review.requestedValue"), requested, struck: false)
                } else {
                    HStack(spacing: Spacing.small) {
                        box(TasksStrings.text("tasks.review.previous"), previous, struck: true)
                        WaiveraIcon(systemName: "chevron.right")
                            .font(.system(size: ControlSize.iconSmall))
                            .foregroundStyle(Palette.textSecondary)
                            .accessibilityHidden(true)
                        box(TasksStrings.text("tasks.review.requestedValue"), requested, struck: false)
                    }
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.mediumSmall)
            .accessibilityElement(children: .combine)
        }

        private func box(_ label: String, _ value: String, struck: Bool) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .waiveraTextStyle(.labelMedium)
                    .foregroundStyle(Palette.textSecondary)
                Text(value)
                    .waiveraTextStyle(.bodyLarge)
                    .foregroundStyle(struck ? Palette.textSecondary : Palette.text)
                    .strikethrough(struck)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.mediumSmall)
            .padding(.vertical, Spacing.small)
            .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
    }
#endif
