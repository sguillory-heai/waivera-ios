#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// Request time off (Android `TimeOffFormSheet`): leave type, full or partial day, the dates,
    /// what the server says about them and a note, with Send pinned under it all so a long note
    /// never pushes it out of reach.
    struct TimeOffFormSheet: View {
        let model: TimeOffFormModel
        let zone: TimeZone

        @State private var picking: TimeOffPicking?

        private var state: TimeOffFormState { model.state }

        var body: some View {
            VStack(spacing: Spacing.mediumSmall) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                        Text(TimeOffStrings.text("profile.leave.request"))
                            .waiveraTextStyle(.titleLarge, weight: .bold)
                            .foregroundStyle(Palette.text)
                            .accessibilityAddTraits(.isHeader)
                        typeField
                        SegmentedControl(
                            options: [
                                .init(false, title: TimeOffStrings.text("profile.leave.fullDay")),
                                .init(true, title: TimeOffStrings.text("profile.leave.partialDay")),
                            ],
                            selection: Binding(get: { state.partialDay }, set: { model.setPartialDay($0) })
                        )
                        if state.partialDay { partialDayFields } else { fullDayFields }
                        TimeOffFindings(state: state, onRetryCheck: { model.retryCheck() })
                        note
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, Spacing.gutter)
                }
                if let failure = state.failure {
                    BannerView(.error, message: TimeOffStrings.failure(failure.problem))
                        .padding(.horizontal, Spacing.gutter)
                }
                WaiveraButton(
                    TimeOffStrings.text("profile.leave.send"),
                    size: .large,
                    isLoading: state.sending,
                    loadingTitle: TimeOffStrings.text("profile.leave.sending"),
                    fillsWidth: true
                ) {
                    model.send()
                }
                .disabled(!state.canSend)
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.medium)
            }
            .background(Palette.surface)
            .sheet(item: $picking) { pick in
                picker(pick)
            }
        }

        @ViewBuilder private var typeField: some View {
            switch state.types {
            case .loading:
                SkeletonBlock(height: ControlSize.fieldHeight, cornerRadius: Radius.field)
                    .accessibilityLabel(Text(TimeOffStrings.text("profile.leave.leaveType")))
            case .failed:
                BannerView(
                    .error,
                    message: TimeOffStrings.text("profile.leave.typesFailed"),
                    actionTitle: TimeOffStrings.text("profile.leave.tryAgain"),
                    action: { model.loadTypes() }
                )
            case .ready:
                TimeOffPickerField(
                    label: TimeOffStrings.text("profile.leave.leaveType"),
                    value: state.type.map {
                        TimeOffStrings.format("profile.leave.typeValue", $0.name, TimeOffStrings.balance($0))
                    },
                    placeholder: TimeOffStrings.text("profile.leave.pickType"),
                    systemImage: "chevron.down",
                    disabled: state.sending
                ) {
                    picking = .type
                }
            }
        }

        private var fullDayFields: some View {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Spacing.small) { fullDays }
                VStack(spacing: Spacing.small) { fullDays }
            }
        }

        @ViewBuilder private var fullDays: some View {
            TimeOffPickerField(
                label: TimeOffStrings.text("profile.leave.firstDay"),
                value: state.firstDay.map(dayText),
                placeholder: TimeOffStrings.text("profile.leave.pickStart"),
                systemImage: "calendar",
                disabled: state.sending
            ) {
                picking = .firstDay
            }
            TimeOffPickerField(
                label: TimeOffStrings.text("profile.leave.lastDay"),
                value: state.lastDay.map(dayText),
                placeholder: TimeOffStrings.text("profile.leave.pickEnd"),
                systemImage: "calendar",
                error: state.issue == .endBeforeStart ? TimeOffStrings.text("profile.leave.issueOrder") : nil,
                disabled: state.sending
            ) {
                picking = .lastDay
            }
        }

        @ViewBuilder private var partialDayFields: some View {
            TimeOffPickerField(
                label: TimeOffStrings.text("profile.leave.date"),
                value: state.day.map(dayText),
                placeholder: TimeOffStrings.text("profile.leave.pickDate"),
                systemImage: "calendar",
                disabled: state.sending
            ) {
                picking = .day
            }
            HStack(alignment: .top, spacing: Spacing.small) {
                TimeOffPickerField(
                    label: TimeOffStrings.text("profile.leave.from"),
                    value: state.from.map(timeText),
                    placeholder: TimeOffStrings.text("profile.leave.pickStart"),
                    systemImage: "clock",
                    disabled: state.sending
                ) {
                    picking = .from
                }
                TimeOffPickerField(
                    label: TimeOffStrings.text("profile.leave.to"),
                    value: state.to.map(timeText),
                    placeholder: TimeOffStrings.text("profile.leave.pickEnd"),
                    systemImage: "clock",
                    disabled: state.sending
                ) {
                    picking = .to
                }
            }
        }

        private var note: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(TimeOffStrings.text("profile.leave.note"))
                    .waiveraTextStyle(.fieldLabel)
                    .foregroundStyle(Palette.textSecondary)
                TextField(
                    TimeOffStrings.text("profile.leave.noteHint"),
                    text: Binding(get: { state.note }, set: { model.setNote($0) }),
                    axis: .vertical
                )
                .lineLimit(2...6)
                .textInputAutocapitalization(.sentences)
                .waiveraTextStyle(.bodyLarge)
                .padding(Spacing.medium)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                .disabled(state.sending)
            }
        }

        @ViewBuilder
        private func picker(_ pick: TimeOffPicking) -> some View {
            let today = state.today
            switch pick {
            case .type:
                if case .ready(let types) = state.types {
                    LeaveTypeList(types: types, selectedId: state.typeId) { id in
                        model.pickType(id)
                        picking = nil
                    }
                }
            case .firstDay:
                daySheet(TimeOffStrings.text("profile.leave.firstDay"), state.firstDay ?? today) {
                    model.pickFirstDay($0)
                }
            case .lastDay:
                daySheet(
                    TimeOffStrings.text("profile.leave.lastDay"),
                    state.lastDay ?? state.firstDay ?? today,
                    earliest: state.firstDay
                ) { model.pickLastDay($0) }
            case .day:
                daySheet(TimeOffStrings.text("profile.leave.date"), state.day ?? today) { model.pickDay($0) }
            case .from:
                timeSheet(TimeOffStrings.text("profile.leave.pickFrom"), state.from ?? Self.defaultFrom) {
                    model.pickFrom($0)
                }
            case .to:
                let initial = state.to ?? state.from.map { $0 + 60 } ?? Self.defaultTo
                timeSheet(TimeOffStrings.text("profile.leave.pickTo"), initial) {
                    model.pickTo($0)
                }
            }
        }

        private static let defaultFrom = 9 * 60
        private static let defaultTo = 17 * 60

        private func daySheet(
            _ title: String,
            _ initial: CalendarDate,
            earliest: CalendarDate? = nil,
            onPicked: @escaping (CalendarDate) -> Void
        ) -> some View {
            TimeOffPickerSheet(
                title: title,
                initial: initial.startInstant(in: zone),
                components: .date,
                zone: zone,
                earliest: earliest?.startInstant(in: zone)
            ) { picked in
                onPicked(CalendarDate(picked, in: zone))
            }
        }

        private func timeSheet(_ title: String, _ minutes: Int, onPicked: @escaping (Int) -> Void) -> some View {
            let day = state.day ?? state.today
            return TimeOffPickerSheet(
                title: title,
                initial: TimeOffDrafts.instant(day, minutes: minutes, zone: zone) ?? day.startInstant(in: zone),
                components: .hourAndMinute,
                zone: zone
            ) { picked in
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                let parts = calendar.dateComponents([.hour, .minute], from: picked)
                onPicked((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        }

        /// "Tue, Nov 24", with the year when it is not this one.
        private func dayText(_ day: CalendarDate) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.setLocalizedDateFormatFromTemplate(day.year == state.today.year ? "EEEMMMd" : "EEEMMMdyyyy")
            return formatter.string(from: Date(timeIntervalSince1970: Double(day.daysSinceEpoch) * 86_400 + 43_200))
        }

        /// "9:30 AM", always 12-hour.
        private func timeText(_ minutes: Int) -> String {
            let hour = minutes / 60
            let twelve = hour % 12 == 0 ? 12 : hour % 12
            let suffix = hour < 12 ? "AM" : "PM"
            return String(format: "%d:%02d %@", twelve, minutes % 60, suffix)
        }
    }
#endif
