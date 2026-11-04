#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The quick event sheet (Android `EventFormSheet`): title, one day with times in the saved
    /// zone, video or a place, notes and invitees. Repeats and linked tasks are on the web.
    struct EventFormSheet: View {
        let model: EventFormModel
        let onClose: () -> Void
        let onSaved: (EventSaved) -> Void

        @Environment(\.openURL) private var openURL

        var body: some View {
            let form = model.state
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        EventFormWhenFields(form: form, model: model)
                        EventFormPlaceFields(form: form, model: model)
                        EventFormInviteSection(form: form, model: model)
                        if form.saveFailed {
                            BannerView(.error, message: ScheduleStrings.text("schedule.form.saveFailed"))
                        }
                        WaiveraButton(
                            ScheduleStrings.text(form.isEdit ? "schedule.form.save" : "schedule.form.create"),
                            isLoading: form.isSaving,
                            loadingTitle: ScheduleStrings.text("schedule.form.saving"),
                            fillsWidth: true
                        ) {
                            model.save()
                        }
                        .accessibilityIdentifier("schedule.form.save")
                        if let web = model.webCalendarURL {
                            WaiveraButton(
                                ScheduleStrings.text("schedule.form.onWeb"),
                                variant: .text,
                                systemImage: "safari"
                            ) {
                                openURL(web)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(Spacing.gutter)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Palette.surface)
                .navigationTitle(ScheduleStrings.text(form.isEdit ? "schedule.editEvent" : "schedule.newEvent"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ScheduleStrings.text("schedule.close"), action: onClose)
                            .disabled(form.isSaving)
                    }
                }
            }
            .interactiveDismissDisabled(form.isSaving)
            .task { await model.loadDirectory() }
            .onChange(of: model.saved) { _, saved in
                if let saved { onSaved(saved) }
            }
        }
    }

    /// The small pieces every form section shares.
    enum EventFormParts {
        static func label(_ text: String) -> some View {
            Text(text)
                .waiveraTextStyle(.labelLarge, weight: .semibold)
                .foregroundStyle(Palette.text)
        }

        static func error(_ text: String) -> some View {
            Text(text)
                .waiveraTextStyle(.bodySmall, weight: .semibold)
                .foregroundStyle(Palette.dangerText)
        }

        static func note(_ text: String) -> some View {
            Text(text)
                .waiveraTextStyle(.bodySmall)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        static func field(_ placeholder: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
            TextField(placeholder, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 3...8 : 1...1)
                .waiveraTextStyle(.bodyLarge)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.mediumSmall)
                .frame(minHeight: ControlSize.fieldHeight)
                .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
        }

        static func toggle(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(title)
                        .waiveraTextStyle(.bodyLarge)
                        .foregroundStyle(Palette.text)
                    if let subtitle {
                        Text(subtitle)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .tint(Palette.accent)
            .frame(minHeight: ControlSize.minHitTarget)
        }
    }
#endif
