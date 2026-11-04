#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Invite people (Android `Invitees`): the search field, matches floating on one lifted card,
    /// then who is invited in two colour-coded groups (coworkers violet, participants teal, on the
    /// same gradient tiles as the avatars), and the Email participants switch once a participant
    /// is on the list.
    struct EventFormInviteSection: View {
        let form: EventFormState
        let model: EventFormModel

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            WaiveraTextField(
                ScheduleStrings.text("schedule.form.invite"),
                text: Binding(get: { form.query }, set: { model.setQuery($0) }),
                placeholder: ScheduleStrings.text("schedule.form.invite.placeholder"),
                keyboard: .webSearch,
                systemImage: "magnifyingglass",
                accessibilityIdentifier: "schedule.form.invite.search"
            )
            if form.directoryFailed {
                BannerView(
                    .error,
                    message: ScheduleStrings.text("schedule.form.directoryFailed"),
                    actionTitle: ScheduleStrings.text("schedule.retry"),
                    action: { Task { await model.loadDirectory() } }
                )
            }
            if !form.query.trimmingCharacters(in: .whitespaces).isEmpty {
                if form.matches.isEmpty, !form.directoryFailed {
                    EventFormParts.note(ScheduleStrings.text("schedule.form.invite.none"))
                }
                if !form.matches.isEmpty {
                    matches
                }
            }
            group(isParticipant: false, form.coworkers)
            group(isParticipant: true, form.participants)
            if form.hasParticipants {
                EventFormParts.toggle(
                    ScheduleStrings.text("schedule.form.notify"),
                    subtitle: form.notifyNote,
                    isOn: Binding(get: { form.notifyParticipants }, set: { model.setNotifyParticipants($0) })
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }

        /// Search results on one lifted card, so they read as choices, not as invitees.
        private var matches: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(spacing: Spacing.small) {
                    WaiveraIcon(systemName: "magnifyingglass", pointSize: ControlSize.fieldTileGlyph * 0.8)
                        .foregroundStyle(Palette.textSecondary)
                    Text(matchesCount)
                        .font(WaiveraFont.label)
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
                ForEach(form.matches, id: \.key) { person in
                    InviteeRow(person: person, adding: true) { model.invite(person) }
                }
            }
            .padding(.horizontal, Spacing.mediumSmall)
            .padding(.vertical, Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .shadow(
                color: Palette.liftShadow,
                radius: Elevation.shadow(for: Elevation.card).radius,
                x: 0,
                y: Elevation.shadow(for: Elevation.card).y
            )
        }

        private var matchesCount: String {
            let key = form.matches.count == 1 ? "schedule.form.matches.one" : "schedule.form.matches.other"
            return ScheduleStrings.format(key, form.matches.count)
        }

        /// Coworkers on a violet tint, participants on a teal one, so who is staff and who is a
        /// client reads at a glance without a tag on every row.
        @ViewBuilder private func group(isParticipant: Bool, _ people: [AttendeeOption]) -> some View {
            if !people.isEmpty {
                let tone: TileTone = isParticipant ? .teal : .brand
                let title = ScheduleStrings.text(
                    isParticipant ? "schedule.form.group.participants" : "schedule.form.group.coworkers"
                )
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Spacing.small) {
                        IconTile(
                            systemImage: isParticipant ? "person" : "building.2",
                            tone: tone,
                            size: ControlSize.iconTileSmall,
                            glyphSize: ControlSize.fieldTileGlyph
                        )
                        Text(ScheduleStrings.format("schedule.form.group.count", title, people.count))
                            .font(WaiveraFont.label)
                            .foregroundStyle(tone.contentColor)
                    }
                    .padding(.bottom, Spacing.extraSmall)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(people, id: \.key) { person in
                        InviteeRow(person: person, adding: false) { model.uninvite(person) }
                    }
                }
                .padding(.horizontal, Spacing.mediumSmall)
                .padding(.vertical, Spacing.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    tone.containerColor.opacity(Self.groupTint),
                    in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                )
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: people.count)
            }
        }

        /// Android's `GROUP_TINT_ALPHA`.
        private static let groupTint = 0.35
    }

    /// One person (Android `InviteeRow`): the avatar on the kind's gradient tile, the name, the
    /// kind while choosing, the email, and Add or Remove.
    private struct InviteeRow: View {
        let person: AttendeeOption
        let adding: Bool
        let action: () -> Void

        private var actionLabel: String {
            ScheduleStrings.format(adding ? "schedule.form.invite.add" : "schedule.form.invite.remove", person.name)
        }

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                AvatarView(
                    name: person.name,
                    size: ControlSize.avatarSmall,
                    tileIndex: person.isParticipant ? AvatarTiles.teal : AvatarTiles.violet
                )
                .padding(.top, Spacing.xxSmall)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(person.name)
                        .waiveraTextStyle(.titleSmall)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                    if adding {
                        Text(
                            ScheduleStrings.text(
                                person.isParticipant ? "schedule.form.kind.participant" : "schedule.form.kind.coworker"
                            )
                        )
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(person.isParticipant ? TileTone.teal.contentColor : Palette.textSecondary)
                    }
                    if let email = person.email, !email.isEmpty {
                        Text(email)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                Button(action: action) {
                    WaiveraIcon(systemName: adding ? "plus" : "xmark")
                        .foregroundStyle(adding ? Palette.accent : Palette.textSecondary)
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
                .frame(maxHeight: .infinity)
                .accessibilityLabel(Text(actionLabel))
            }
            .padding(.vertical, Spacing.xxSmall)
        }
    }
#endif
