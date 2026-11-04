#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Title, day, all day and the start and end times. The pickers show the saved zone, not the
    /// device's, so a person travelling sets the time their schedule uses.
    struct EventFormWhenFields: View {
        let form: EventFormState
        let model: EventFormModel

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                EventFormParts.label(ScheduleStrings.text("schedule.form.title"))
                EventFormParts.field(
                    ScheduleStrings.text("schedule.form.title.placeholder"),
                    text: Binding(get: { form.title }, set: { model.setTitle($0) })
                )
                .accessibilityIdentifier("schedule.form.title")
                if form.showErrors, form.titleMissing {
                    EventFormParts.error(ScheduleStrings.text("schedule.form.title.required"))
                }
            }
            VStack(alignment: .leading, spacing: Spacing.small) {
                DatePicker(
                    ScheduleStrings.text("schedule.form.day"),
                    selection: Binding(get: { form.dayInstant }, set: { model.setDate($0) }),
                    displayedComponents: .date
                )
                EventFormParts.toggle(
                    ScheduleStrings.text("schedule.form.allDay"),
                    isOn: Binding(get: { form.allDay }, set: { model.setAllDay($0) })
                )
                if !form.allDay {
                    DatePicker(
                        ScheduleStrings.text("schedule.form.starts"),
                        selection: Binding(get: { form.startInstant }, set: { model.setStart($0) }),
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        ScheduleStrings.text("schedule.form.ends"),
                        selection: Binding(get: { form.endInstant }, set: { model.setEnd($0) }),
                        displayedComponents: .hourAndMinute
                    )
                    if form.showErrors, form.endBeforeStart {
                        EventFormParts.error(ScheduleStrings.text("schedule.form.endBeforeStart"))
                    }
                }
                EventFormParts.note(form.zoneNote)
            }
            .waiveraTextStyle(.bodyLarge)
            .tint(Palette.accent)
            .environment(\.timeZone, form.zone)
        }
    }

    /// Waivera video or a place, then notes.
    struct EventFormPlaceFields: View {
        let form: EventFormState
        let model: EventFormModel

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                EventFormParts.toggle(
                    ScheduleStrings.text("schedule.form.video"),
                    subtitle: ScheduleStrings.text("schedule.form.video.subtitle"),
                    isOn: Binding(get: { form.waiveraVideo }, set: { model.setVideo($0) })
                )
                if !form.waiveraVideo {
                    EventFormParts.label(ScheduleStrings.text("schedule.form.location"))
                    EventFormParts.field(
                        ScheduleStrings.text("schedule.form.location.placeholder"),
                        text: Binding(get: { form.location }, set: { model.setLocation($0) })
                    )
                }
            }
            VStack(alignment: .leading, spacing: Spacing.small) {
                EventFormParts.label(ScheduleStrings.text("schedule.form.notes"))
                EventFormParts.field(
                    ScheduleStrings.text("schedule.form.notes.placeholder"),
                    text: Binding(get: { form.notes }, set: { model.setNotes($0) }),
                    axis: .vertical
                )
            }
        }
    }
#endif
