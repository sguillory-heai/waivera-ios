#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The casework Delays choice: show delayed tasks in their own group, hide them, or list only
    /// them. Picking one closes the sheet; it never vibrates.
    struct DelaysSheet: View {
        let selected: DelayFilter
        let onSelect: (DelayFilter) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(TasksStrings.text("tasks.delays.sheetTitle"))
                    .waiveraTextStyle(.titleMedium, weight: .bold)
                    .foregroundStyle(Palette.text)
                    .padding(Spacing.gutter)
                    .accessibilityAddTraits(.isHeader)
                ForEach(DelayFilter.allCases, id: \.self) { filter in
                    Button {
                        onSelect(filter)
                    } label: {
                        HStack(spacing: Spacing.mediumSmall) {
                            WaiveraIcon(systemName: filter == selected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(filter == selected ? Palette.accent : Palette.textTertiary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                                Text(Self.title(filter))
                                    .waiveraTextStyle(.bodyLarge, weight: .semibold)
                                    .foregroundStyle(Palette.text)
                                Text(Self.note(filter))
                                    .waiveraTextStyle(.bodySmall)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.vertical, Spacing.mediumSmall)
                        .frame(minHeight: ControlSize.listRowMinHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.row))
                    .accessibilityAddTraits(filter == selected ? [.isSelected] : [])
                }
            }
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.medium)
            .background(Palette.surface)
        }

        static func chipTitle(_ filter: DelayFilter) -> String {
            switch filter {
            case .show: TasksStrings.text("tasks.delays.show")
            case .hide: TasksStrings.text("tasks.delays.hide")
            case .only: TasksStrings.text("tasks.delays.only")
            }
        }

        static func title(_ filter: DelayFilter) -> String {
            switch filter {
            case .show: TasksStrings.text("tasks.delays.show.title")
            case .hide: TasksStrings.text("tasks.delays.hide.title")
            case .only: TasksStrings.text("tasks.delays.only.title")
            }
        }

        static func note(_ filter: DelayFilter) -> String {
            switch filter {
            case .show: TasksStrings.text("tasks.delays.show.note")
            case .hide: TasksStrings.text("tasks.delays.hide.note")
            case .only: TasksStrings.text("tasks.delays.only.note")
            }
        }
    }

    #if DEBUG
        #Preview("Delays") { DelaysSheet(selected: .hide, onSelect: { _ in }) }
        #Preview("Delays dark") { DelaysSheet(selected: .show, onSelect: { _ in }).preferredColorScheme(.dark) }
        #Preview("Delays AX5") {
            DelaysSheet(selected: .only, onSelect: { _ in }).dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
