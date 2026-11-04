#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Android's picker field: the label, then a field showing the value with its icon. A tap
    /// opens the system calendar or time wheel in a sheet, like Android's picker dialog.
    struct EventFormPickerField: View {
        let label: String
        let value: String
        let systemImage: String
        let selection: Binding<Date>
        let components: DatePickerComponents
        let zone: TimeZone
        var error: String?

        @State private var isPicking = false

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                EventFormParts.label(label)
                    .accessibilityHidden(true)
                Button {
                    isPicking = true
                } label: {
                    HStack(spacing: Spacing.small) {
                        WaiveraIcon(systemName: systemImage)
                            .foregroundStyle(Palette.textSecondary)
                        Text(value)
                            .font(WaiveraFont.body)
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Spacing.smallPlus)
                    .frame(maxWidth: .infinity, minHeight: ControlSize.fieldHeight)
                    .fieldBox()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(label))
                .accessibilityValue(Text(value))
                .accessibilityAddTraits(.isButton)
                if let error {
                    EventFormParts.error(error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $isPicking) {
                picker
            }
        }

        private var picker: some View {
            NavigationStack {
                Group {
                    if components == .date {
                        DatePicker(label, selection: selection, displayedComponents: components)
                            .datePickerStyle(.graphical)
                    } else {
                        DatePicker(label, selection: selection, displayedComponents: components)
                            .datePickerStyle(.wheel)
                    }
                }
                .labelsHidden()
                .environment(\.timeZone, zone)
                .tint(Palette.accent)
                .padding(.horizontal, Spacing.gutter)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Palette.surface)
                .navigationTitle(label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ScheduleStrings.text("schedule.form.done")) { isPicking = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
#endif
