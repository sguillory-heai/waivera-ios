#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Previous / title / Next. The buttons keep 44pt targets; the title wraps at large sizes.
    struct PeriodNavigator: View {
        let title: String
        let onStep: (Int) -> Void

        var body: some View {
            HStack(spacing: Spacing.small) {
                stepButton(systemImage: "chevron.left", label: "schedule.previous", direction: -1)
                Text(title)
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                stepButton(systemImage: "chevron.right", label: "schedule.next", direction: 1)
            }
        }

        private func stepButton(systemImage: String, label: String, direction: Int) -> some View {
            Button {
                onStep(direction)
            } label: {
                Image(systemName: systemImage)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(Palette.accent)
                    .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                    .background(Palette.accentSoft, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel(Text(ScheduleStrings.text(label)))
        }
    }
#endif
