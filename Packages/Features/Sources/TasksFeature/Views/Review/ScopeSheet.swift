#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// This step, or every remaining stage at once (Android `ChooseScopeContent`). The everyday
    /// answer leads; the bigger one sits under it with what it does, so the bar stays two buttons.
    struct ScopeSheet: View {
        let stages: Int
        let submit: Bool
        let onChoose: (_ all: Bool) -> Void

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                    Text(TasksStrings.text(submit ? "tasks.review.scopeSubmitTitle" : "tasks.review.scopeTitle"))
                        .waiveraTextStyle(.titleLarge)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    WaiveraButton(
                        TasksStrings.text(submit ? "tasks.review.submit" : "tasks.review.scopeThis"),
                        size: .large,
                        systemImage: "checkmark",
                        fillsWidth: true
                    ) { onChoose(false) }
                    .accessibilityIdentifier("review.scope.this")
                    WaiveraButton(
                        submit
                            ? TasksStrings.text("tasks.review.submitAll")
                            : TasksStrings.plural("tasks.review.approveAll", stages),
                        variant: .secondary,
                        size: .large,
                        fillsWidth: true
                    ) { onChoose(true) }
                    .accessibilityIdentifier("review.scope.all")
                    Text(TasksStrings.text("tasks.review.scopeAllNote"))
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Spacing.large)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.surface)
        }
    }
#endif
