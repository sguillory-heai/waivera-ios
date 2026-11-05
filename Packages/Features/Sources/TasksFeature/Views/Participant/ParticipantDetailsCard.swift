#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Birth date, waiver, region, intake and compliance, each only when the record has it.
    struct ParticipantDetailsCard: View {
        let profile: ParticipantProfile

        var body: some View {
            SheetCardGroup {
                VStack(spacing: 0) {
                    ParticipantDateRow(
                        systemImage: "birthday.cake",
                        label: TasksStrings.text("tasks.participant.birth"),
                        date: profile.birthDate
                    )
                    if let waiver = profile.waiver {
                        InsetDivider()
                        textRow("person.text.rectangle", "tasks.participant.waiver", waiver)
                    }
                    if let region = profile.region {
                        InsetDivider()
                        textRow("mappin.and.ellipse", "tasks.participant.region", region)
                    }
                    if let intake = profile.intake {
                        InsetDivider()
                        textRow("number", "tasks.participant.intake", intake)
                    }
                    InsetDivider()
                    compliance
                }
                .padding(.vertical, Spacing.mediumSmall)
            }
        }

        private func textRow(_ systemImage: String, _ key: String, _ value: String) -> some View {
            FactRow(systemImage: systemImage, label: TasksStrings.text(key)) { FactValue(text: value) }
        }

        private var compliance: some View {
            FactRow(
                systemImage: profile.compliant ? "checkmark" : "exclamationmark.triangle",
                label: TasksStrings.text("tasks.participant.compliance"),
                tone: profile.compliant ? .brand : .danger
            ) {
                FactValue(
                    text: TasksStrings.text(
                        profile.compliant ? "tasks.participant.compliant" : "tasks.participant.notCompliant"
                    )
                )
                if !profile.compliant { FactNote(text: TasksStrings.text("tasks.participant.notCompliantNote")) }
            }
        }
    }

    #if DEBUG
        #Preview("Participant cards") {
            ScrollView {
                VStack(spacing: Spacing.medium) {
                    ParticipantIdentity(
                        profile: ParticipantProfile(id: 1, name: "Sam Ortiz", initials: "SO", changePending: true)
                    )
                    ParticipantDetailsCard(
                        profile: ParticipantProfile(id: 1, name: "Sam Ortiz", initials: "SO", compliant: false)
                    )
                }
                .padding(Spacing.gutter)
            }
            .background(Palette.background)
        }
    #endif
#endif
