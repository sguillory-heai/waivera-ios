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
                    VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                        EventFormWhenFields(form: form, model: model)
                        EventFormInviteSection(form: form, model: model)
                        EventFormPlaceFields(form: form, model: model)
                        if !form.isEdit, let web = model.webCalendarURL {
                            WaiveraButton(
                                ScheduleStrings.text("schedule.form.onWeb"),
                                variant: .text,
                                systemImage: "arrow.up.right.square",
                                fillsWidth: true
                            ) {
                                openURL(web)
                            }
                        }
                    }
                    .padding(Spacing.gutter)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // Android keeps Create under the form, outside the scroll; a failed save
                    // says so right above it, where the person just tapped.
                    VStack(spacing: Spacing.small) {
                        if form.saveFailed {
                            BannerView(.error, message: ScheduleStrings.text("schedule.form.saveFailed"))
                        }
                        saveButton
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.mediumSmall)
                    .background(Palette.surface)
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

        private var saveButton: some View {
            let form = model.state
            return WaiveraButton(
                ScheduleStrings.text(form.isEdit ? "schedule.form.save" : "schedule.form.create"),
                size: .large,
                isLoading: form.isSaving,
                loadingTitle: ScheduleStrings.text("schedule.form.saving"),
                fillsWidth: true
            ) {
                model.save()
            }
            .accessibilityIdentifier("schedule.form.save")
        }
    }

    extension View {
        /// The field fill with its hairline border (`WaiveraTextField`'s box).
        func fieldBox() -> some View {
            let shape = RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
            return background(Palette.field, in: shape)
                .overlay(shape.strokeBorder(Palette.fieldBorder, lineWidth: ControlSize.fieldBorder))
        }
    }

    /// The small pieces every form section shares.
    @MainActor
    enum EventFormParts {
        /// A field's label, as `WaiveraTextField` draws it (Android `WaiveraTextField`).
        static func label(_ text: String) -> some View {
            Text(text)
                .font(WaiveraFont.label)
                .foregroundStyle(Palette.textSecondary)
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

        /// A text box drawn like `WaiveraTextField`'s (field fill, hairline border, 12pt corners),
        /// for the multi-line notes the shared field doesn't take.
        static func field(_ placeholder: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
            TextField(
                placeholder,
                text: text,
                prompt: Text(placeholder).foregroundStyle(Palette.textSecondary),
                axis: axis
            )
            .lineLimit(axis == .vertical ? 3...8 : 1...1)
            .font(WaiveraFont.body)
            .foregroundStyle(Palette.text)
            .tint(Palette.accent)
            .padding(.horizontal, Spacing.smallPlus)
            .padding(.vertical, Spacing.mediumSmall)
            .frame(minHeight: ControlSize.fieldHeight)
            .fieldBox()
        }

        static func toggle(
            _ title: String,
            subtitle: String? = nil,
            tile: (systemImage: String, tone: TileTone)? = nil,
            isOn: Binding<Bool>
        ) -> some View {
            Toggle(isOn: isOn) {
                HStack(spacing: ControlSize.fieldTileGap) {
                    if let tile {
                        IconTile(
                            systemImage: tile.systemImage,
                            tone: tile.tone,
                            size: ControlSize.fieldTile,
                            glyphSize: ControlSize.fieldTileGlyph
                        )
                    }
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
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
            }
            .toggleStyle(.waivera)
            .frame(minHeight: ControlSize.minHitTarget)
        }
    }
#endif
