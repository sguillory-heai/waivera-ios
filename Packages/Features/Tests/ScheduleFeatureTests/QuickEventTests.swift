import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ScheduleFeature

@MainActor
@Suite("Quick events")
struct QuickEventTests {
    private func utc(_ text: String) -> Date { WaiveraInstant.parse(text) ?? .distantPast }

    private func event(_ id: String = "e1", owner: String? = DemoData.viewerId) -> CalendarEvent {
        var event = CalendarEvent(
            id: id,
            title: "Mine",
            start: utc("2026-11-03T15:00:00Z"),
            end: utc("2026-11-03T16:00:00Z")
        )
        event.ownerId = owner
        event.isOwner = owner == DemoData.viewerId
        return event
    }

    @Test("Manage: own one-off single-day events edit here, the rest go to the web")
    func manageRules() {
        let me = DemoData.viewerId
        #expect(EventRules.manage(event(), myUserId: me, zone: Zones.chicago) == .edit)
        #expect(EventRules.manage(event(owner: "usr_priya_raman"), myUserId: me, zone: Zones.chicago) == nil)
        var repeating = event()
        repeating.recurrenceRule = "FREQ=WEEKLY"
        #expect(EventRules.manage(repeating, myUserId: me, zone: Zones.chicago) == .webOnly)
        var task = event()
        task.taskId = 12
        #expect(EventRules.manage(task, myUserId: me, zone: Zones.chicago) == .webOnly)
        let occurrence = event("3f2a9c1e-0b7d-4e55-9a41-7c2d8e6f1a00-2026-11-03T15:00:00Z")
        #expect(EventRules.manage(occurrence, myUserId: me, zone: Zones.chicago) == .webOnly)
        var overnight = event()
        overnight.end = utc("2026-11-04T07:00:00Z")
        #expect(EventRules.manage(overnight, myUserId: me, zone: Zones.chicago) == .webOnly)
        // The repeated hour on 1 Nov: 00:30 CDT to 01:30 CST is still one day in Chicago.
        var repeatedHour = event()
        repeatedHour.start = utc("2026-11-01T05:30:00Z")
        repeatedHour.end = utc("2026-11-01T07:30:00Z")
        #expect(EventRules.manage(repeatedHour, myUserId: me, zone: Zones.chicago) == .edit)
        var allDay = event()
        allDay.allDay = CalendarEvent.AllDaySpan(
            start: CalendarDate(year: 2026, month: 11, day: 3)!,
            endExclusive: CalendarDate(year: 2026, month: 11, day: 4)!
        )
        #expect(EventRules.manage(allDay, myUserId: me, zone: Zones.chicago) == .edit)
    }

    @Test("A new event today starts at the next half hour in the saved zone, on the DST change day")
    func newEventDefaults() {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        let model = EventFormModel(calendar: fake.calendar, clock: fake.clock)
        // DemoData.now is 09:00 CST on 1 Nov 2026, the fall-back day.
        #expect(model.state.date == DemoData.today)
        #expect(model.state.startMinute == 9 * 60 + 30)
        #expect(model.state.endMinute == 10 * 60)
        #expect(model.state.startInstant == utc("2026-11-01T15:30:00Z"))
        let later = EventFormModel(date: DemoData.today.adding(days: 1), calendar: fake.calendar, clock: fake.clock)
        #expect(later.state.startMinute == 9 * 60)
        #expect(!model.state.isValid)
    }

    @Test("Moving the start keeps the length; a missing title blocks the save")
    func editingFields() {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        let model = EventFormModel(date: DemoData.today.adding(days: 2), calendar: fake.calendar, clock: fake.clock)
        model.setEnd(model.state.date.instant(atMinute: 10 * 60, in: Zones.chicago))
        model.setStart(model.state.date.instant(atMinute: 13 * 60, in: Zones.chicago))
        #expect(model.state.startMinute == 13 * 60)
        #expect(model.state.endMinute == 14 * 60)
        model.setStart(model.state.date.instant(atMinute: 23 * 60 + 30, in: Zones.chicago))
        #expect(model.state.endMinute == 23 * 60 + 59)
        model.save()
        #expect(model.state.showErrors)
        #expect(model.state.titleMissing)
        model.setTitle(String(repeating: "a", count: 300))
        #expect(model.state.title.count == 200)
    }

    @Test("Invite search matches names and emails and hides people already invited")
    func inviteSearch() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        let model = EventFormModel(calendar: fake.calendar, clock: fake.clock)
        await model.loadDirectory()
        #expect(model.state.matches.isEmpty)
        model.setQuery("example")
        #expect(model.state.matches.count == 3)
        let morgan = try? #require(model.state.matches.first { $0.isParticipant })
        if let morgan { model.invite(morgan) }
        #expect(model.state.query.isEmpty)
        #expect(model.state.hasParticipants)
        model.setQuery("morgan")
        #expect(model.state.matches.isEmpty)
    }

    @Test("Create sends a draft with participants and the email switch")
    func create() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        await fake.environment.launch()
        let model = EventFormModel(date: DemoData.today.adding(days: 1), calendar: fake.calendar, clock: fake.clock)
        await model.loadDirectory()
        model.setTitle("Family visit")
        model.setQuery("Morgan")
        if let morgan = model.state.matches.first { model.invite(morgan) }
        model.setQuery("Jordan")
        if let jordan = model.state.matches.first { model.invite(jordan) }
        model.setNotifyParticipants(true)
        model.setVideo(false)
        model.setLocation("North house")
        model.save()
        #expect(await eventually { model.saved != nil })
        #expect(model.saved?.created == true)
        let draft = fake.calendar.savedDrafts.get().last
        #expect(draft?.participantIds == ["par_morgan_hale"])
        #expect(draft?.inviteeIds == ["usr_jordan_lee"])
        #expect(draft?.notifyParticipants == true)
        #expect(draft?.location == "North house")
        #expect(draft?.startMinute == 9 * 60)
    }

    @Test("A failed save keeps the form and says so; editing clears it")
    func saveFailure() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        fake.calendar.controls.update { $0.failure = .offline }
        let model = EventFormModel(calendar: fake.calendar, clock: fake.clock)
        model.setTitle("Check-in")
        model.save()
        #expect(await eventually { model.state.saveFailed })
        #expect(!model.state.isSaving)
        #expect(model.saved == nil)
        model.setTitle("Check-in 2")
        #expect(!model.state.saveFailed)
    }

    @Test("Edit opens on your own demo event, saves it and the event screen shows the change")
    func editAndCancelFromTheEventScreen() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        await fake.environment.launch()
        let screen = CalendarEventModel(
            eventID: "evt_demo_checkin",
            calendar: fake.calendar,
            conversations: fake.chat,
            session: fake.session,
            clock: fake.clock,
            deviceZone: { Zones.chicago },
            locale: english
        )
        let observer = Task { await screen.observe() }
        defer { observer.cancel() }
        #expect(await eventually { screen.editableEvent != nil })
        guard let event = screen.editableEvent else { return }
        let form = EventFormModel(event: event, calendar: fake.calendar, clock: fake.clock)
        #expect(form.state.isEdit)
        // 20:00Z on 1 Nov is 2 PM CST, after the fall-back change.
        #expect(form.state.startMinute == 14 * 60)
        #expect(form.state.endMinute == 15 * 60)
        form.setTitle("North team sync")
        form.save()
        #expect(await eventually { form.saved?.created == false })
        #expect(
            await eventually {
                if case .loaded(let details) = screen.state { return details.title == "North team sync" }
                return false
            }
        )
        screen.cancelEvent()
        #expect(await eventually { screen.closeRequest != nil })
        #expect(fake.calendar.calls.all.contains("cancelEvent:evt_demo_checkin"))
    }

    @Test("A failed cancel keeps the event and shows the failure")
    func cancelFailure() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        await fake.environment.launch()
        let screen = CalendarEventModel(eventID: "evt_demo_checkin", data: fake.environment)
        let observer = Task { await screen.observe() }
        defer { observer.cancel() }
        #expect(await eventually { screen.editableEvent != nil })
        fake.calendar.controls.update { $0.failure = .offline }
        screen.cancelEvent()
        #expect(
            await eventually {
                if case .loaded(let details) = screen.state { return details.cancelFailure != nil }
                return false
            }
        )
        #expect(screen.closeRequest == nil)
        #expect(screen.failureTicks == 1)
    }

    @Test("Someone else's event offers nothing to manage")
    func inviteeCannotManage() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        await fake.environment.launch()
        let screen = CalendarEventModel(eventID: "evt_demo_invite", data: fake.environment)
        let observer = Task { await screen.observe() }
        defer { observer.cancel() }
        #expect(
            await eventually {
                if case .loaded(let details) = screen.state { return details.manage == nil }
                return false
            }
        )
        #expect(screen.editableEvent == nil)
    }
}
