#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// Ask for a change: the chooser (more time, report a delay, close) and each form. The rules
    /// match the web's: a new due date after the current one, a reason, an explanation of at
    /// most 4,000 characters, and a file on the task when the reason needs one.
    struct AskChangeSheet: View {
        let form: AskForm
        let today: CalendarDate?
        let zone: TimeZone
        let model: TaskDetailModel

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        if let kind = form.kind {
                            fields(kind)
                        } else {
                            chooser
                        }
                    }
                    .padding(Spacing.gutter)
                }
                .background(Palette.surface)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if form.kind != nil, form.choices.count > 1 {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                model.backToChoices()
                            } label: {
                                WaiveraIcon(systemName: "chevron.left")
                            }
                            .accessibilityLabel(Text(TasksStrings.text("tasks.ask.back")))
                        }
                    }
                }
            }
        }

        private var title: String {
            switch form.kind {
            case .moreTime: TasksStrings.text("tasks.ask.moreTime.title")
            case .delay: TasksStrings.text("tasks.ask.delay")
            case .closure: TasksStrings.text("tasks.ask.closure")
            case nil: TasksStrings.text("tasks.ask.title")
            }
        }

        private var chooser: some View {
            CardGroup {
                ForEach(form.choices, id: \.self) { kind in
                    ListRow(title: kind.title, subtitle: kind.detail, showsChevron: true) {
                        IconTile(
                            systemImage: icon(kind),
                            tone: kind == .closure ? .rose : (kind == .delay ? .amber : .brand),
                            size: ControlSize.fieldTile,
                            glyphSize: ControlSize.fieldTileGlyph
                        )
                    } trailing: {
                        EmptyView()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.chooseAsk(kind) }
                    .accessibilityAddTraits(.isButton)
                }
            }
        }

        private func icon(_ kind: AskKind) -> String {
            switch kind {
            case .moreTime: "calendar.badge.clock"
            case .delay: "clock.badge.exclamationmark"
            case .closure: "xmark.circle"
            }
        }

        @ViewBuilder
        private func fields(_ kind: AskKind) -> some View {
            if let due = form.currentDue, let today {
                Text(TasksStrings.format("tasks.ask.dueLine", TaskFormat.date(due, today: today)))
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.textSecondary)
            }
            switch kind {
            case .moreTime: newDue
            case .delay: delayWindow
            case .closure: EmptyView()
            }
            reasons(kind)
            explanation(kind)
            if form.needsEvidence { evidence }
            if form.failed { error(TasksStrings.text("tasks.ask.failed")) }
            WaiveraButton(
                TasksStrings.text(kind == .delay ? "tasks.ask.report" : "tasks.ask.send"),
                isLoading: form.isSaving,
                fillsWidth: true
            ) {
                model.submitAsk()
            }
            .disabled(kind == .delay && form.delay == nil)
            Text(TasksStrings.text(kind == .closure ? "tasks.ask.closure.note" : "tasks.ask.moreTime.note"))
                .waiveraTextStyle(.bodySmall)
                .foregroundStyle(Palette.textSecondary)
        }

        @ViewBuilder private var newDue: some View {
            label(TasksStrings.text("tasks.ask.newDue"))
            DatePicker(
                TasksStrings.text("tasks.ask.newDue"),
                selection: Binding(
                    get: {
                        (form.newDue ?? form.currentDue?.adding(days: 1) ?? today)?.startInstant(in: zone) ?? Date()
                    },
                    set: { model.setAskDue(CalendarDate($0, in: zone)) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .environment(\.timeZone, zone)
            if form.showErrors {
                if form.dueMissing { error(TasksStrings.text("tasks.ask.dueRequired")) }
                if form.dueTooEarly, let due = form.currentDue, let today {
                    error(TasksStrings.format("tasks.ask.dueAfter", TaskFormat.date(due, today: today)))
                }
                if form.dueTooLate { error(TasksStrings.text("tasks.ask.dueWithin")) }
            }
        }

        @ViewBuilder private var delayWindow: some View {
            label(TasksStrings.text("tasks.ask.delayWindow"))
            if let period = form.delay, let today {
                CardGroup {
                    FactRow(systemImage: "calendar", label: TasksStrings.text("tasks.ask.delayStarts")) {
                        FactValue(text: TaskFormat.date(period.start, today: today))
                    }
                    FactRow(
                        systemImage: "calendar.badge.checkmark",
                        label: TasksStrings.text("tasks.ask.delayThrough")
                    ) {
                        FactValue(text: TaskFormat.date(period.end, today: today))
                    }
                }
                Text(TasksStrings.text("tasks.ask.delayFixed"))
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                error(TasksStrings.text("tasks.ask.delayClosed"))
            }
            if form.delayChanged { error(TasksStrings.text("tasks.ask.delayChanged")) }
        }

        @ViewBuilder
        private func reasons(_ kind: AskKind) -> some View {
            label(TasksStrings.text(Self.reasonKey(kind)))
            switch form.reasons {
            case .loading:
                SkeletonBlock(height: ControlSize.fieldHeight)
            case .failed:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.ask.reasonsError"),
                    message: "",
                    onRetry: { model.loadAskReasons() }
                )
            case .ready(let reasons):
                Menu {
                    ForEach(reasons) { reason in
                        Button(reason.name) { model.setAskReason(reason.id) }
                    }
                } label: {
                    HStack {
                        Text(form.reason?.name ?? TasksStrings.text("tasks.ask.chooseReason"))
                            .foregroundStyle(form.reason == nil ? Palette.textTertiary : Palette.text)
                        Spacer()
                        WaiveraIcon(systemName: "chevron.up.chevron.down").foregroundStyle(Palette.textSecondary)
                    }
                    .waiveraTextStyle(.bodyLarge)
                    .padding(.horizontal, Spacing.medium)
                    .frame(minHeight: ControlSize.fieldHeight)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                }
                if let detail = form.reason?.description {
                    Text(detail).waiveraTextStyle(.bodySmall).foregroundStyle(Palette.textSecondary)
                }
                if form.showErrors, form.reasonMissing { error(TasksStrings.text("tasks.ask.reasonRequired")) }
            }
        }

        @ViewBuilder
        private func explanation(_ kind: AskKind) -> some View {
            let optional = kind == .closure && form.reason?.needsComment != true
            label(TasksStrings.text(Self.explanationKey(kind, optional: optional)))
            TextField(
                TasksStrings.text(Self.explanationKey(kind, optional: false) + ".placeholder"),
                text: Binding(get: { form.explanation }, set: { model.setAskExplanation($0) }),
                axis: .vertical
            )
            .lineLimit(3...8)
            .waiveraTextStyle(.bodyLarge)
            .padding(Spacing.medium)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
            if form.explanationTooLong {
                error(TasksStrings.plural("tasks.ask.explanationOver", form.explanation.count - AskForm.maxExplanation))
            } else if form.showErrors, form.explanationMissing {
                error(
                    TasksStrings.text(kind == .closure ? "tasks.ask.commentRequired" : "tasks.ask.explanationRequired")
                )
            }
        }

        @ViewBuilder private var evidence: some View {
            label(TasksStrings.text("tasks.ask.evidence"))
            switch form.files {
            case .loading:
                SkeletonBlock(height: ControlSize.fieldHeight)
            case .failed:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.ask.filesError"),
                    message: "",
                    onRetry: { model.loadAskFiles() }
                )
            case .ready(let files) where files.isEmpty:
                error(TasksStrings.text("tasks.ask.noFiles"))
            case .ready(let files):
                Menu {
                    ForEach(files) { file in
                        Button(file.name) { model.setAskEvidence(file.attachmentId) }
                    }
                } label: {
                    HStack {
                        WaiveraIcon(systemName: "paperclip")
                        Text(form.evidence?.name ?? TasksStrings.text("tasks.ask.chooseFile"))
                        Spacer()
                    }
                    .waiveraTextStyle(.bodyLarge)
                    .foregroundStyle(form.evidence == nil ? Palette.textTertiary : Palette.text)
                    .padding(.horizontal, Spacing.medium)
                    .frame(minHeight: ControlSize.fieldHeight)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                }
                if form.showErrors, form.evidenceMissing { error(TasksStrings.text("tasks.ask.evidenceRequired")) }
            }
        }

        static func reasonKey(_ kind: AskKind) -> String {
            switch kind {
            case .moreTime: "tasks.ask.reasonCode"
            case .delay: "tasks.ask.delayReason"
            case .closure: "tasks.ask.closureReason"
            }
        }

        static func explanationKey(_ kind: AskKind, optional: Bool) -> String {
            switch kind {
            case .moreTime: "tasks.ask.justification"
            case .delay: "tasks.ask.explanation"
            case .closure: optional ? "tasks.ask.commentsOptional" : "tasks.ask.comments"
            }
        }

        private func label(_ text: String) -> some View {
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
