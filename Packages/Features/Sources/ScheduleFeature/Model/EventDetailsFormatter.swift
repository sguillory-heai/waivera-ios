import Foundation
import WaiveraAPI
import WaiveraData

/// Everything the event screen layers over the server's event.
struct EventInteraction: Sendable, Hashable {
    var optimistic: OptimisticResponse?
    var failure: ResponseFailure?
    var joinBusy = false
    var joinError: JoinError?
    var chatBusy = false
    var chatError: WaiveraError?
}

/// Builds `EventDetailsUI` from the event, the rules and the schedule zone.
struct EventDetailsFormatter {
    var zone: ScheduleZone
    var deviceZone: TimeZone
    var now: Date
    var myUserId: String?
    var milestones: MilestoneCalendar

    func details(
        _ event: CalendarEvent,
        interaction: EventInteraction,
        refreshFailed: Bool,
        text: ScheduleText
    ) -> EventDetailsUI {
        let timeZone = zone.timeZone
        let today = CalendarDate(now, in: timeZone)
        let isOrganizer = EventRules.isOrganizer(event, myUserId: myUserId)
        var invitation = EventRules.invitation(
            event,
            myUserId: myUserId,
            now: now,
            zone: timeZone,
            optimistic: interaction.optimistic
        )
        invitation?.failure = interaction.failure
        let join = EventRules.join(event, now: now, isBusy: interaction.joinBusy, error: interaction.joinError)
        let attendees = EventRules.attendees(
            event,
            myUserId: myUserId,
            optimistic: interaction.optimistic,
            milestones: milestones,
            today: today
        )
        let time = timeLines(event, today: today, text: text)
        return EventDetailsUI(
            eventId: event.id,
            title: event.title ?? ScheduleStrings.untitledEvent,
            zoneNotice: ScheduleStateBuilder.zoneNotice(zone: zone, deviceZone: deviceZone, text: text),
            ownerColor: ScheduleCopy.ownerColor(event.ownerColor),
            organizer: organizer(event, isOrganizer: isOrganizer, today: today),
            isOrganizer: isOrganizer,
            timePrimary: time.primary,
            timeSecondary: time.secondary,
            isOnline: event.isOnline || event.isSprout,
            location: event.isOnline ? (event.location ?? event.meetingDetails) : event.location,
            details: event.details,
            taskTitle: event.taskTitle,
            attendees: attendees.map(person),
            attendeeCount: ScheduleStrings.count("schedule.event.attendees", attendees.count),
            invitation: invitation,
            invitationStatus: invitation.map(invitationStatus),
            invitationFailure: invitation?.failure.map {
                ScheduleStrings.format("schedule.response.failed", $0.error.userMessage)
            },
            join: join,
            joinNote: join.flatMap { joinNote($0, text: text) },
            joinError: join?.error.map(joinErrorText),
            canMessageOrganizer: EventRules.canMessageOrganizer(event, myUserId: myUserId),
            isOpeningChat: interaction.chatBusy,
            chatError: interaction.chatError.map { ScheduleStrings.format("schedule.chat.failed", $0.userMessage) },
            refreshNotice: refreshFailed ? ScheduleStrings.text("schedule.event.refreshFailed") : nil
        )
    }

    /// Timed: "Sun, Nov 1, 10:00 AM" / "Until 10:30 AM" (with the date when it ends on another
    /// day). All day: the literal dates, never shifted.
    func timeLines(_ event: CalendarEvent, today: CalendarDate, text: ScheduleText) -> (
        primary: String, secondary: String?
    ) {
        switch ScheduleAgenda.timing(of: event, zone: zone.timeZone, day: today) {
        case .allDay(let start, let endInclusive):
            let first = text.shortDay(start, currentYear: today.year)
            guard endInclusive > start else { return (first, ScheduleStrings.text("schedule.allDay")) }
            let last = text.shortDay(endInclusive, currentYear: today.year)
            return (first, ScheduleStrings.format("schedule.until", last))
        case .timed(let start, let end, _, _):
            let primary = text.dateTime(start, currentYear: today.year)
            guard end > start else { return (primary, nil) }
            let sameDay = CalendarDate(start, in: zone.timeZone) == CalendarDate(end, in: zone.timeZone)
            let until = sameDay ? text.clock(end) : text.dateTime(end, currentYear: today.year)
            return (primary, ScheduleStrings.format("schedule.until", until))
        }
    }

    private func organizer(_ event: CalendarEvent, isOrganizer: Bool, today: CalendarDate) -> EventDetailsUI.Person? {
        if isOrganizer {
            let name = ScheduleStrings.text("schedule.event.youOrganize")
            return .init(id: "organizer", userId: myUserId, name: name, accessibilityLabel: name)
        }
        guard event.ownerId != nil || event.ownerName != nil else { return nil }
        let name = event.ownerName ?? ScheduleStrings.text("schedule.celebration.nameFallback")
        let celebration = milestones.celebration(for: event.ownerId, on: today)
        let label = celebration.map { CelebrationText($0, name: name).accessible } ?? name
        return .init(
            id: "organizer",
            userId: event.ownerId,
            name: name,
            celebration: celebration,
            accessibilityLabel: [ScheduleStrings.text("schedule.event.organizedBy"), label]
                .joined(separator: ScheduleStrings.text("schedule.list.separator"))
        )
    }

    private func person(_ row: AttendeeRow) -> EventDetailsUI.Person {
        let base = row.name ?? row.email ?? ScheduleStrings.text("schedule.event.guest")
        let name = row.isMe ? ScheduleStrings.format("schedule.event.you", base) : base
        let status = Self.statusText(row.response)
        var parts = [name]
        if let status { parts.append(status) }
        if let celebration = row.celebration { parts.append(CelebrationText(celebration, name: base).accessible) }
        return .init(
            id: row.id,
            userId: row.userId,
            name: name,
            detail: status,
            celebration: row.celebration,
            accessibilityLabel: parts.joined(separator: ScheduleStrings.text("schedule.list.separator"))
        )
    }

    static func statusText(_ response: InvitationState) -> String? {
        switch response {
        case .pending: ScheduleStrings.text("schedule.status.invited")
        case .accepted: ScheduleStrings.text("schedule.status.accepted")
        case .declined: ScheduleStrings.text("schedule.status.declined")
        case .tentative: ScheduleStrings.text("schedule.status.tentative")
        case .cancelled: ScheduleStrings.text("schedule.status.cancelled")
        case .unknown: ScheduleStrings.text("schedule.status.unknown")
        case .notInvited: nil
        }
    }

    private func invitationStatus(_ invitation: InvitationUI) -> String {
        if invitation.phase == .saving { return ScheduleStrings.text("schedule.response.saving") }
        if !invitation.canChange { return ScheduleStrings.text("schedule.response.started") }
        switch invitation.response {
        case .accepted: return ScheduleStrings.text("schedule.response.accepted")
        case .declined: return ScheduleStrings.text("schedule.response.declined")
        case .tentative: return ScheduleStrings.text("schedule.response.tentative")
        default: return ScheduleStrings.text("schedule.response.pending")
        }
    }

    private func joinNote(_ join: JoinUI, text: ScheduleText) -> String? {
        switch join.state {
        case .open: nil
        case .tooEarly:
            join.opensAt.map { opensAt in
                let isToday = CalendarDate(opensAt, in: zone.timeZone) == CalendarDate(now, in: zone.timeZone)
                let when =
                    isToday
                    ? text.clock(opensAt)
                    : text.dateTime(opensAt, currentYear: CalendarDate(now, in: zone.timeZone).year)
                return ScheduleStrings.format("schedule.join.opens", when)
            }
        case .ended: ScheduleStrings.text("schedule.join.ended")
        case .noTime: ScheduleStrings.text("schedule.join.noTime")
        }
    }

    private func joinErrorText(_ error: JoinError) -> String {
        let reason: String =
            switch error {
            case .noLink: ScheduleStrings.text("schedule.join.noLink")
            case .failed(let underlying?): underlying.userMessage
            case .failed(nil): ScheduleStrings.text("schedule.join.openFailed")
            }
        return ScheduleStrings.format("schedule.join.failed", reason)
    }
}
