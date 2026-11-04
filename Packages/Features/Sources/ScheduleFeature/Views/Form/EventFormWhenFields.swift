#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Title, All day, the day, then Starts and Ends side by side, and the zone note (Android's
    /// order). The pickers show the saved zone, not the device's, so a person travelling sets the
    /// time their schedule uses.
    struct EventFormWhenFields: View {
        let form: EventFormState
        let model: EventFormModel

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            WaiveraTextField(
                ScheduleStrings.text("schedule.form.title"),
                text: Binding(get: { form.title }, set: { model.setTitle($0) }),
                placeholder: ScheduleStrings.text("schedule.form.title.placeholder"),
                error: titleError,
                accessibilityIdentifier: "schedule.form.title"
            )
            EventFormParts.toggle(
                ScheduleStrings.text("schedule.form.allDay"),
                isOn: Binding(get: { form.allDay }, set: { model.setAllDay($0) })
            )
            EventFormPickerField(
                label: ScheduleStrings.text("schedule.form.day"),
                value: form.dayText,
                systemImage: "calendar",
                selection: Binding(get: { form.dayInstant }, set: { model.setDate($0) }),
                components: .date,
                zone: form.zone
            )
            if !form.allDay {
                times
            }
            EventFormParts.note(form.zoneNote)
        }

        private var titleError: String? {
            form.showErrors && form.titleMissing ? ScheduleStrings.text("schedule.form.title.required") : nil
        }

        private var endError: String? {
            form.showErrors && form.endBeforeStart ? ScheduleStrings.text("schedule.form.endBeforeStart") : nil
        }

        /// Starts and Ends side by side, stacked at accessibility text sizes.
        private var timesLayout: AnyLayout {
            if dynamicTypeSize.isAccessibilitySize {
                return AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.mediumSmall))
            }
            return AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.mediumSmall))
        }

        private var times: some View {
            timesLayout {
                EventFormPickerField(
                    label: ScheduleStrings.text("schedule.form.starts"),
                    value: form.startText,
                    systemImage: "clock",
                    selection: Binding(get: { form.startInstant }, set: { model.setStart($0) }),
                    components: .hourAndMinute,
                    zone: form.zone
                )
                EventFormPickerField(
                    label: ScheduleStrings.text("schedule.form.ends"),
                    value: form.endText,
                    systemImage: "clock",
                    selection: Binding(get: { form.endInstant }, set: { model.setEnd($0) }),
                    components: .hourAndMinute,
                    zone: form.zone,
                    error: endError
                )
            }
        }
    }

    /// Waivera video (with its tile) or a place, then notes.
    struct EventFormPlaceFields: View {
        let form: EventFormState
        let model: EventFormModel

        var body: some View {
            EventFormParts.toggle(
                ScheduleStrings.text("schedule.form.video"),
                subtitle: ScheduleStrings.text("schedule.form.video.subtitle"),
                tile: ("video", .brand),
                isOn: Binding(get: { form.waiveraVideo }, set: { model.setVideo($0) })
            )
            if !form.waiveraVideo {
                WaiveraTextField(
                    ScheduleStrings.text("schedule.form.location"),
                    text: Binding(get: { form.location }, set: { model.setLocation($0) }),
                    placeholder: ScheduleStrings.text("schedule.form.location.placeholder")
                )
            }
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                EventFormParts.label(ScheduleStrings.text("schedule.form.notes"))
                    .accessibilityHidden(true)
                EventFormParts.field(
                    ScheduleStrings.text("schedule.form.notes.placeholder"),
                    text: Binding(get: { form.notes }, set: { model.setNotes($0) }),
                    axis: .vertical
                )
                .accessibilityLabel(Text(ScheduleStrings.text("schedule.form.notes")))
            }
        }
    }
#endif
