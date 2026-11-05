#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// Who this is, at a glance: teal initials (the participant colour, never a coworker's avatar,
    /// so people we serve and staff stay distinct), the name and only the badges that matter today.
    struct ParticipantIdentity: View {
        let profile: ParticipantProfile

        var body: some View {
            HStack(spacing: Spacing.medium) {
                Text(profile.initials)
                    .waiveraTextStyle(.titleLarge, weight: .semibold)
                    .dynamicTypeSize(.large)
                    .foregroundStyle(TileTone.teal.contentColor)
                    .frame(width: ControlSize.avatarLarge, height: ControlSize.avatarLarge)
                    .background(
                        TileTone.teal.containerColor,
                        in: RoundedRectangle(
                            cornerRadius: AvatarGeometry.cornerRadius(size: ControlSize.avatarLarge),
                            style: .continuous
                        )
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(profile.name)
                        .waiveraTextStyle(.titleLarge)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    if profile.deactivated || profile.changePending {
                        HStack(spacing: Spacing.small) {
                            if profile.deactivated {
                                StatusBadge(TasksStrings.text("tasks.participant.deactivated"), tone: .neutral)
                            }
                            if profile.changePending {
                                StatusBadge(TasksStrings.text("tasks.participant.changePending"), tone: .warning)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.small)
        }
    }

    /// Mobile and email, each a tap to call or write.
    struct ParticipantContactCard: View {
        let profile: ParticipantProfile
        let onContact: (URL) -> Void

        var body: some View {
            SheetCardGroup {
                VStack(spacing: 0) {
                    if let mobile = profile.mobile {
                        contactRow(
                            systemImage: "phone",
                            label: TasksStrings.text("tasks.participant.mobile"),
                            value: mobile,
                            hint: TasksStrings.format("tasks.participant.call", profile.name),
                            url: ParticipantModel.callURL(mobile)
                        )
                    }
                    if profile.mobile != nil, profile.email != nil { InsetDivider() }
                    if let email = profile.email {
                        contactRow(
                            systemImage: "envelope",
                            label: TasksStrings.text("tasks.participant.email"),
                            value: email,
                            hint: TasksStrings.format("tasks.participant.write", profile.name),
                            url: ParticipantModel.mailURL(email)
                        )
                    }
                }
                .padding(.vertical, Spacing.mediumSmall)
            }
        }

        @ViewBuilder
        private func contactRow(systemImage: String, label: String, value: String, hint: String, url: URL?)
            -> some View
        {
            let row = FactRow(systemImage: systemImage, label: label) { FactValue(text: value, color: Palette.accent) }
            if let url {
                Button { onContact(url) } label: { row.contentShape(Rectangle()) }
                    .buttonStyle(.press(.card))
                    .accessibilityHint(Text(hint))
            } else {
                row
            }
        }
    }

    /// The plan (CPOC) with how long its year has left, then certification and linkage.
    struct ParticipantPlanCard: View {
        let profile: ParticipantProfile
        let plan: PlanStatus?

        var body: some View {
            SheetCardGroup {
                VStack(spacing: 0) {
                    FactRow(systemImage: "calendar", label: TasksStrings.text("tasks.participant.plan")) {
                        FactValue(text: range)
                        if let plan {
                            FactNote(text: plan.text, color: plan.ended ? Palette.dangerText : Palette.textSecondary)
                        }
                    }
                    InsetDivider()
                    ParticipantDateRow(
                        systemImage: "person.text.rectangle",
                        label: TasksStrings.text("tasks.participant.certification"),
                        date: profile.certification
                    )
                    InsetDivider()
                    ParticipantDateRow(
                        systemImage: "house",
                        label: TasksStrings.text("tasks.participant.linkage"),
                        date: profile.linkage
                    )
                }
                .padding(.vertical, Spacing.mediumSmall)
            }
        }

        private var range: String {
            let notSet = TasksStrings.text("tasks.participant.notSet")
            let start = profile.planStart.map(TaskFormat.fullDate)
            let end = profile.planEnd.map(TaskFormat.fullDate)
            if start == nil, end == nil { return notSet }
            return TasksStrings.format("tasks.participant.planRange", start ?? notSet, end ?? notSet)
        }
    }

    struct ParticipantDateRow: View {
        let systemImage: String
        let label: String
        let date: CalendarDate?

        var body: some View {
            FactRow(systemImage: systemImage, label: label) {
                FactValue(text: date.map(TaskFormat.fullDate) ?? TasksStrings.text("tasks.participant.notSet"))
            }
        }
    }
#endif
