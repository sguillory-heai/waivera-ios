import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TasksFeature

/// Mirrors Android `ParticipantViewModelTest`: loading, content, empty, error, forbidden and a
/// retry, plus the plan year's wording across a daylight saving change.
@MainActor
struct ParticipantModelTests {
    @Test func loadsTheProfileThenTheirOpenTasks() async {
        let fakes = FakeDataEnvironment.make()
        let model = ParticipantModel(participantId: 501, environment: fakes.environment)
        #expect(model.state.phase == .loading)
        model.load()
        #expect(await eventually { model.state.tasks.value != nil })
        #expect(model.state.phase == .content)
        #expect(model.state.profile?.name == "Jordan Lee")
        let rows = model.state.tasks.value ?? []
        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.about == "Jordan Lee" })
        #expect(model.state.overdue == rows.filter { $0.daysLate != nil }.count)
        #expect(model.state.plan != nil)
    }

    @Test func aParticipantWithNoOpenTasksShowsTheEmptyList() async {
        let fakes = FakeDataEnvironment.make()
        fakes.participants.profiles.update {
            $0[600] = ParticipantProfile(id: 600, name: "Riley Brooks", initials: "RB", deactivated: true)
        }
        let model = ParticipantModel(participantId: 600, environment: fakes.environment)
        model.load()
        #expect(await eventually { model.state.tasks.value != nil })
        #expect(model.state.tasks == .ready([]))
        #expect(model.state.overdue == 0)
        #expect(model.state.plan == nil)
        #expect(model.state.profile?.deactivated == true)
    }

    @Test func aParticipantOutsideTheViewersRolesIsForbidden() async {
        let fakes = FakeDataEnvironment.make()
        fakes.participants.hidden.update { $0 = [502] }
        let model = ParticipantModel(participantId: 502, environment: fakes.environment)
        model.load()
        #expect(await eventually { model.state.phase == .forbidden })
        #expect(fakes.participants.calls.count("tasks:502") == 0)
    }

    @Test func aFailedLoadCanBeRetried() async {
        let fakes = FakeDataEnvironment.make()
        fakes.participants.failure.update { $0 = .offline }
        let model = ParticipantModel(participantId: 501, environment: fakes.environment)
        model.load()
        #expect(await eventually { model.state.phase == .error })
        fakes.participants.failure.update { $0 = nil }
        model.load()
        #expect(model.state.phase == .loading)
        #expect(await eventually { model.state.phase == .content })
    }

    @Test func openTasksThatFailKeepTheProfileAndRetry() async {
        let fakes = FakeDataEnvironment.make()
        fakes.participants.tasksFailure.update { $0 = .server(statusCode: 503) }
        let model = ParticipantModel(participantId: 501, environment: fakes.environment)
        model.load()
        #expect(await eventually { model.state.tasks == .failed })
        #expect(model.state.phase == .content)
        fakes.participants.tasksFailure.update { $0 = nil }
        model.loadTasks()
        #expect(await eventually { model.state.tasks.value != nil })
    }

    @Test func aRefreshThatFailsKeepsWhatIsOnScreen() async {
        let fakes = FakeDataEnvironment.make()
        let model = ParticipantModel(participantId: 501, environment: fakes.environment)
        model.load()
        #expect(await eventually { model.state.phase == .content })
        fakes.participants.failure.update { $0 = .offline }
        model.load()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.state.phase == .content)
        #expect(model.state.profile?.id == 501)
    }

    /// US clocks fall back on 2026-11-01; days are still whole calendar days.
    @Test func planStatusCountsCalendarDaysAcrossADaylightSavingChange() {
        let today = CalendarDate(year: 2026, month: 10, day: 31) ?? DemoData.today
        #expect(PlanStatus.of(end: today.adding(days: 2), today: today) == .endsIn(days: 2))
        #expect(PlanStatus.of(end: today.adding(days: 1), today: today).text == "Ends tomorrow")
        #expect(PlanStatus.of(end: today, today: today) == .endsToday)
        #expect(PlanStatus.of(end: today.adding(days: -1), today: today).text == "Ended yesterday")
        #expect(PlanStatus.of(end: today.adding(days: -9), today: today) == .endedAgo(days: 9))
        #expect(PlanStatus.of(end: today.adding(days: -9), today: today).ended)
    }

    @Test func contactLinksKeepOnlyWhatTheyNeed() {
        #expect(ParticipantModel.callURL("(555) 010-2231")?.absoluteString == "tel:5550102231")
        #expect(ParticipantModel.callURL("ext") == nil)
        #expect(ParticipantModel.mailURL("jordan.lee@example.com")?.absoluteString == "mailto:jordan.lee@example.com")
        #expect(ParticipantModel.mailURL("not an email") == nil)
    }

    @Test func theSnapshotOpensOnTheWebOnlyWhenConfigured() {
        let fakes = FakeDataEnvironment.make()
        let model = ParticipantModel(participantId: 501, environment: fakes.environment)
        let url = model.webURL()
        if fakes.environment.webBaseURL != nil {
            #expect(url?.path == "/participant/501/participant-snapshot")
        } else {
            #expect(url == nil)
        }
    }
}
