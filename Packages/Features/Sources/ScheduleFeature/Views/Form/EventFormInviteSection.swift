#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Invite people: search the directory, see who is invited grouped by kind, and the Email
    /// participants switch once a participant is on the list.
    struct EventFormInviteSection: View {
        let form: EventFormState
        let model: EventFormModel

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                EventFormParts.label(ScheduleStrings.text("schedule.form.invite"))
                if form.directoryFailed {
                    BannerView(
                        .error,
                        message: ScheduleStrings.text("schedule.form.directoryFailed"),
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { Task { await model.loadDirectory() } }
                    )
                } else {
                    SearchField(
                        ScheduleStrings.text("schedule.form.invite"),
                        placeholder: ScheduleStrings.text("schedule.form.invite.placeholder"),
                        query: Binding(get: { form.query }, set: { model.setQuery($0) }),
                        identifier: "schedule.form.invite.search"
                    )
                    matches
                }
                group("schedule.form.group.coworkers", form.coworkers)
                group("schedule.form.group.participants", form.participants)
                if form.hasParticipants {
                    EventFormParts.toggle(
                        ScheduleStrings.text("schedule.form.notify"),
                        subtitle: form.notifyNote,
                        isOn: Binding(get: { form.notifyParticipants }, set: { model.setNotifyParticipants($0) })
                    )
                }
            }
        }

        @ViewBuilder private var matches: some View {
            if !form.query.trimmingCharacters(in: .whitespaces).isEmpty {
                if form.matches.isEmpty {
                    EventFormParts.note(ScheduleStrings.text("schedule.form.invite.none"))
                } else {
                    CardGroup {
                        ForEach(form.matches, id: \.key) { person in
                            Button {
                                model.invite(person)
                            } label: {
                                PersonLine(person: person, systemImage: "plus.circle")
                            }
                            .buttonStyle(.press(.row))
                            .accessibilityLabel(Text(ScheduleStrings.format("schedule.form.invite.add", person.name)))
                        }
                    }
                }
            }
        }

        @ViewBuilder private func group(_ key: String, _ people: [AttendeeOption]) -> some View {
            if !people.isEmpty {
                SectionHeader(
                    ScheduleStrings.format("schedule.form.group.count", ScheduleStrings.text(key), people.count)
                )
                CardGroup {
                    ForEach(people, id: \.key) { person in
                        Button {
                            model.uninvite(person)
                        } label: {
                            PersonLine(person: person, systemImage: "xmark.circle")
                        }
                        .buttonStyle(.press(.row))
                        .accessibilityLabel(Text(ScheduleStrings.format("schedule.form.invite.remove", person.name)))
                    }
                }
            }
        }
    }

    /// One person: avatar, name, the kind, and the add or remove glyph.
    private struct PersonLine: View {
        let person: AttendeeOption
        let systemImage: String

        var body: some View {
            HStack(spacing: Spacing.mediumSmall) {
                AvatarView(name: person.name, size: ControlSize.avatarSmall)
                VStack(alignment: .leading, spacing: 0) {
                    Text(person.name)
                        .waiveraTextStyle(.bodyLarge)
                        .foregroundStyle(Palette.text)
                    Text(
                        ScheduleStrings.text(
                            person.isParticipant ? "schedule.form.kind.participant" : "schedule.form.kind.coworker"
                        )
                    )
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: Spacing.small)
                Image(systemName: systemImage)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: ControlSize.minHitTarget + Spacing.medium)
            .contentShape(Rectangle())
        }
    }
#endif
