#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraDesign

    /// A picker field (Android `WaiveraPickerField`): the label, then the value with its icon. A tap
    /// opens the system calendar or time wheel in a sheet.
    struct TimeOffPickerField: View {
        let label: String
        let value: String?
        let placeholder: String
        let systemImage: String
        var error: String?
        var disabled = false
        let action: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(label)
                    .waiveraTextStyle(.fieldLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                Button(action: action) {
                    HStack(spacing: Spacing.small) {
                        WaiveraIcon(systemName: systemImage)
                            .foregroundStyle(Palette.textSecondary)
                        Text(value ?? placeholder)
                            .waiveraTextStyle(.bodyLarge)
                            .foregroundStyle(value == nil ? Palette.textTertiary : Palette.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Spacing.smallPlus)
                    .frame(maxWidth: .infinity, minHeight: ControlSize.fieldHeight)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                            .strokeBorder(
                                error == nil ? Palette.fieldBorder : Palette.danger,
                                lineWidth: ControlSize.fieldBorder
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
                .disabled(disabled)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(value ?? placeholder))
                .accessibilityAddTraits(.isButton)
                if let error {
                    Text(error)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.dangerText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What a picker sheet edits.
    enum TimeOffPicking: String, Identifiable {
        case type, firstDay, lastDay, day, from, to
        var id: String { rawValue }
    }

    /// The system calendar or time wheel for one field, in the person's saved zone.
    struct TimeOffPickerSheet: View {
        let title: String
        let initial: Date
        let components: DatePickerComponents
        let zone: TimeZone
        var earliest: Date?
        let onPicked: (Date) -> Void

        @Environment(\.dismiss) private var dismiss
        @State private var picked: Date?

        var body: some View {
            NavigationStack {
                Group {
                    if components == .date {
                        if let earliest {
                            DatePicker(title, selection: selection, in: earliest..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                        } else {
                            DatePicker(title, selection: selection, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                        }
                    } else {
                        DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                    }
                }
                .labelsHidden()
                .environment(\.timeZone, zone)
                .tint(Palette.accent)
                .padding(.horizontal, Spacing.gutter)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Palette.surface)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(TimeOffStrings.text("profile.leave.cancel")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(TimeOffStrings.text("profile.leave.done")) {
                            onPicked(picked ?? initial)
                            dismiss()
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }

        private var selection: Binding<Date> {
            Binding(get: { picked ?? initial }, set: { picked = $0 })
        }
    }
#endif
