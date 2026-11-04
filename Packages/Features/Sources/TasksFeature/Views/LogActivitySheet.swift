#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// Log activity: type, time spent in 15-minute steps, when (in the employee's saved zone,
    /// never in the future) and what was done. A type can lock the time or the description.
    struct LogActivitySheet: View {
        let form: LogForm
        let zone: TimeZone
        let today: CalendarDate?
        let model: TaskDetailModel

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        typePicker
                        minutes
                        when
                        description
                        if form.failed {
                            Text(TasksStrings.text("tasks.log.failed"))
                                .waiveraTextStyle(.bodySmall, weight: .semibold)
                                .foregroundStyle(Palette.dangerText)
                        }
                        WaiveraButton(
                            TasksStrings.text("tasks.log.submit"),
                            isLoading: form.isSaving,
                            loadingTitle: TasksStrings.text("tasks.log.saving"),
                            fillsWidth: true
                        ) {
                            model.submitLog()
                        }
                        Text(TasksStrings.text("tasks.log.fileTypesOnWeb"))
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(Spacing.gutter)
                }
                .background(Palette.surface)
                .navigationTitle(TasksStrings.text("tasks.log.title"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }

        @ViewBuilder private var typePicker: some View {
            fieldLabel(TasksStrings.text("tasks.log.type"))
            switch form.types {
            case .loading:
                SkeletonBlock(height: ControlSize.fieldHeight)
            case .failed:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.log.typesError"),
                    message: "",
                    onRetry: { model.loadTypes() }
                )
            case .ready(let types):
                Menu {
                    ForEach(types) { type in
                        Button(type.name) { model.chooseType(type.id) }
                    }
                } label: {
                    HStack {
                        Text(form.type?.name ?? TasksStrings.text("tasks.log.typePlaceholder"))
                            .foregroundStyle(form.type == nil ? Palette.textTertiary : Palette.text)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").foregroundStyle(Palette.textSecondary)
                    }
                    .waiveraTextStyle(.bodyLarge)
                    .padding(.horizontal, Spacing.medium)
                    .frame(minHeight: ControlSize.fieldHeight)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                }
                if form.showErrors, form.typeMissing { error(TasksStrings.text("tasks.log.typeRequired")) }
            }
        }

        @ViewBuilder private var minutes: some View {
            fieldLabel(TasksStrings.text("tasks.log.time"))
            HStack(spacing: Spacing.medium) {
                stepButton("minus", label: TasksStrings.text("tasks.log.less"), up: false)
                Text(TaskFormat.duration(form.minutes))
                    .waiveraTextStyle(.titleMedium, weight: .bold)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.updatesFrequently)
                stepButton("plus", label: TasksStrings.text("tasks.log.more"), up: true)
            }
            if form.minutesLocked {
                Text(TasksStrings.text("tasks.log.timeSetByType"))
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
            }
        }

        private func stepButton(_ systemImage: String, label: String, up: Bool) -> some View {
            Button {
                model.stepMinutes(up: up)
            } label: {
                Image(systemName: systemImage)
                    .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                    .background(Palette.accentSoft, in: Circle())
                    .foregroundStyle(Palette.onAccentSoft)
            }
            .buttonStyle(.press(.compact))
            .disabled(form.minutesLocked)
            .accessibilityLabel(Text(label))
        }

        @ViewBuilder private var when: some View {
            fieldLabel(TasksStrings.text("tasks.log.when"))
            DatePicker(
                TasksStrings.text("tasks.log.when"),
                selection: Binding(
                    get: { form.completedAt },
                    set: { picked in
                        let day = CalendarDate(picked, in: zone)
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = zone
                        let parts = calendar.dateComponents([.hour, .minute], from: picked)
                        model.setWhen(date: day, minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                    }
                ),
                in: ...Date(),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .environment(\.timeZone, zone)
            .accessibilityValue(Text(form.whenText))
            if form.inFuture { error(TasksStrings.text("tasks.log.whenFuture")) }
        }

        @ViewBuilder private var description: some View {
            fieldLabel(TasksStrings.text("tasks.log.what"))
            TextField(
                TasksStrings.text("tasks.log.whatPlaceholder"),
                text: Binding(get: { form.description }, set: { model.setDescription($0) }),
                axis: .vertical
            )
            .lineLimit(4...10)
            .waiveraTextStyle(.bodyLarge)
            .padding(Spacing.medium)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
            .disabled(form.descriptionLocked)
            if form.showErrors, form.descriptionMissing { error(TasksStrings.text("tasks.log.whatRequired")) }
        }

        private func fieldLabel(_ text: String) -> some View {
            Text(text)
                .waiveraTextStyle(.labelLarge, weight: .semibold)
                .foregroundStyle(Palette.text)
        }

        private func error(_ text: String) -> some View {
            Text(text)
                .waiveraTextStyle(.bodySmall, weight: .semibold)
                .foregroundStyle(Palette.dangerText)
        }
    }
#endif
