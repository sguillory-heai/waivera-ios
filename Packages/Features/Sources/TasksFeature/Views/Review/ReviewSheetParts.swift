#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// A review sheet's chrome: the title bar, the fields scrolling, and the buttons pinned under
    /// them so a long form never pushes the answer out of reach.
    struct ReviewSheetFrame<Content: View, Bar: View>: View {
        let title: String
        var isSaving = false
        @ViewBuilder let content: () -> Content
        @ViewBuilder let bar: () -> Bar

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.mediumSmall) { content() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.gutter)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: Spacing.small) { bar() }
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.vertical, Spacing.mediumSmall)
                        .background(Palette.surface)
                }
                .background(Palette.surface)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
            }
            .waiveraSheetPresentation()
            .interactiveDismissDisabled(isSaving)
        }
    }

    /// A field's label over it.
    struct ReviewLabel: View {
        let text: String

        init(_ text: String) { self.text = text }

        var body: some View {
            Text(text)
                .waiveraTextStyle(.labelLarge, weight: .semibold)
                .foregroundStyle(Palette.text)
        }
    }

    /// A note under a field: an error in red, a warning in amber, else quiet help.
    struct ReviewNote: View {
        enum Tone { case help, warning, error }

        let text: String
        var tone: Tone = .help

        var body: some View {
            Text(text)
                .waiveraTextStyle(.bodySmall, weight: tone == .error ? .semibold : nil)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }

        private var color: Color {
            switch tone {
            case .help: Palette.textSecondary
            case .warning: Palette.warningText
            case .error: Palette.dangerText
            }
        }
    }

    /// A multi-line text field with its label and the over-the-limit or missing note.
    struct ReviewTextArea: View {
        let label: String
        let placeholder: String
        let text: String
        var error: String?
        var enabled = true
        let onChange: (String) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                ReviewLabel(label)
                TextField(placeholder, text: Binding(get: { text }, set: onChange), axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.sentences)
                    .waiveraTextStyle(.bodyLarge)
                    .padding(Spacing.medium)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                    .disabled(!enabled)
                if let error { ReviewNote(text: error, tone: .error) }
            }
        }

        /// "12 characters over the limit" when `text` is longer than `limit`.
        static func overLimit(_ text: String, limit: Int) -> String? {
            let over = text.count - limit
            return over > 0 ? TasksStrings.plural("tasks.review.textOver", over) : nil
        }
    }

    /// A field that opens a menu of choices, showing the chosen one or a placeholder.
    struct ReviewMenuField<Items: View>: View {
        let label: String
        let value: String?
        let placeholder: String
        var error: String?
        var enabled = true
        @ViewBuilder let items: () -> Items

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                ReviewLabel(label)
                Menu(content: items) {
                    HStack {
                        Text(value ?? placeholder)
                            .foregroundStyle(value == nil ? Palette.textTertiary : Palette.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        WaiveraIcon(systemName: "chevron.up.chevron.down").foregroundStyle(Palette.textSecondary)
                    }
                    .waiveraTextStyle(.bodyLarge)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.vertical, Spacing.small)
                    .frame(minHeight: ControlSize.fieldHeight)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                }
                .disabled(!enabled)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(value ?? placeholder))
                if let error { ReviewNote(text: error, tone: .error) }
            }
        }
    }

    /// A date field: the chosen date (or "Pick a date"), opening a calendar under it. Dates are
    /// literal calendar days, so the calendar reads them in UTC and no zone can shift them.
    struct ReviewDateField: View {
        let label: String
        let value: CalendarDate?
        /// A value that isn't a valid date, shown as typed so the error has context.
        var raw: String?
        let today: CalendarDate
        var error: String?
        var warning: String?
        var enabled = true
        let onPick: (CalendarDate) -> Void

        @State private var isOpen = false

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                ReviewLabel(label)
                Button {
                    isOpen.toggle()
                } label: {
                    HStack {
                        WaiveraIcon(systemName: "calendar").foregroundStyle(Palette.textSecondary)
                        Text(shown ?? TasksStrings.text("tasks.review.pickDate"))
                            .foregroundStyle(shown == nil ? Palette.textTertiary : Palette.text)
                        Spacer()
                        WaiveraIcon(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .waiveraTextStyle(.bodyLarge)
                    .padding(.horizontal, Spacing.medium)
                    .frame(minHeight: ControlSize.fieldHeight)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(shown ?? TasksStrings.text("tasks.review.pickDate")))
                if isOpen {
                    DatePicker(
                        label,
                        selection: Binding(
                            get: { (value ?? today).startInstant(in: .gmt) },
                            set: { onPick(CalendarDate($0, in: .gmt)) }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .environment(\.timeZone, .gmt)
                    .tint(Palette.accent)
                }
                if let error {
                    ReviewNote(text: error, tone: .error)
                } else if let warning {
                    ReviewNote(text: warning, tone: .warning)
                }
            }
        }

        private var shown: String? {
            if let value { return TaskFormat.fullDate(value) }
            return raw.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
    }

    /// A choice card (Android `ChoiceRow`): the chosen one has the accent wash, a stronger edge and
    /// a check.
    struct ChoiceRow: View {
        let title: String
        let detail: String?
        let selected: Bool
        var systemImage = "folder"
        var enabled = true
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack(spacing: Spacing.mediumSmall) {
                    IconTile(
                        systemImage: systemImage,
                        tone: enabled ? .brand : .neutral,
                        size: ControlSize.fieldTile,
                        glyphSize: ControlSize.fieldTileGlyph
                    )
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(title)
                            .waiveraTextStyle(.titleSmall)
                            .foregroundStyle(enabled ? Palette.text : Palette.textSecondary)
                        if let detail {
                            Text(detail).waiveraTextStyle(.bodySmall).foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if selected { WaiveraIcon(systemName: "checkmark").foregroundStyle(Palette.accent) }
                }
                .padding(Spacing.mediumSmall)
                .frame(minHeight: ControlSize.listRowMinHeight)
                .background(
                    selected ? Palette.accentWash : Palette.surface,
                    in: RoundedRectangle(cornerRadius: Radius.sheetCard)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.sheetCard)
                        .strokeBorder(
                            selected ? Palette.accentBorderStrong : Palette.border,
                            lineWidth: selected ? ControlSize.selectedOutline : Spacing.hairline
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.sheetCard))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }
#endif
