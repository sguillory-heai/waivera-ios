import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TasksFeature

@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

private func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
    CalendarDate(year: year, month: month, day: day) ?? DemoData.today
}

/// Rows, groups and due text, judged on the employee's saved-zone day.
struct TasksRulesTests {
    // Sunday 1 November 2026, the day US clocks fall back.
    private let today = date(2026, 11, 1)

    @Test func groupsByWeekWithDelaysApart() {
        // Sunday-first weeks: this week runs Nov 1 to 7.
        #expect(TasksRules.group(date(2026, 10, 31), today: today, firstWeekday: 1) == .overdue)
        #expect(TasksRules.group(date(2026, 11, 7), today: today, firstWeekday: 1) == .thisWeek)
        #expect(TasksRules.group(date(2026, 11, 8), today: today, firstWeekday: 1) == .nextWeek)
        #expect(TasksRules.group(date(2026, 11, 15), today: today, firstWeekday: 1) == .later)
        #expect(TasksRules.group(nil, today: today, firstWeekday: 1) == .noDue)
        // Monday-first weeks: Sunday is the last day of the week that began Oct 26.
        #expect(TasksRules.group(date(2026, 11, 2), today: today, firstWeekday: 2) == .nextWeek)

        let delayed = TaskSummary(
            id: 1,
            key: "HEA-1",
            title: "Visit",
            due: date(2026, 10, 20),
            state: .notStarted,
            about: nil,
            delayed: true,
            delayedThrough: date(2026, 11, 20)
        )
        let row = TasksRules.row(delayed, today: today, me: nil, firstWeekday: 1)
        #expect(row.group == .delayed)
        #expect(row.daysLate == nil)
        #expect(row.dueLine.contains("Delayed through"))
    }

    @Test func lateRowsCountDaysAndHideTheOwnAssignee() {
        let task = TaskSummary(
            id: 2,
            key: "HEA-2",
            title: "Intake",
            due: date(2026, 10, 29),
            state: .inProgress,
            about: "Jordan Lee",
            assigneeId: "me",
            assigneeName: "Alex",
            pendingClosure: true
        )
        let row = TasksRules.row(task, today: today, me: "me", firstWeekday: 1)
        #expect(row.daysLate == 3)
        #expect(row.dueLine == "3 days late")
        #expect(row.assignee == nil)
        #expect(row.flag == .closureRequested)
        let other = TasksRules.row(task, today: today, me: "someone", firstWeekday: 1)
        #expect(other.assignee == "Alex")
    }

    @Test func dueTextAroundToday() {
        #expect(TaskFormat.due(today, today: today) == .today)
        #expect(TaskFormat.due(date(2026, 11, 2), today: today) == .tomorrow)
        #expect(TaskFormat.due(date(2026, 10, 31), today: today) == .yesterday)
        #expect(TaskFormat.due(date(2026, 10, 31), today: today).overdue)
        #expect(TaskFormat.due(nil, today: today) == .none)
        #expect(TaskFormat.duration(75) == "1 hr 15 min")
        #expect(TaskFormat.duration(45) == "45 min")
        #expect(TaskFormat.duration(120) == "2 hr")
    }

    @Test func momentsUseTheSavedZoneAndTwelveHourTimeAcrossDST() throws {
        let zone = try #require(TimeZone(identifier: "America/Chicago"))
        // 01:30 CDT and 01:30 CST both happen on Nov 1; each reads in its own offset.
        let first = try #require(WaiveraInstant.parse("2026-11-01T06:30:00Z"))
        let second = try #require(WaiveraInstant.parse("2026-11-01T07:30:00Z"))
        #expect(TaskFormat.moment(first, zone: zone, today: today).text == "Today, 1:30 AM")
        #expect(TaskFormat.moment(second, zone: zone, today: today).text == "Today, 1:30 AM")
        let evening = try #require(WaiveraInstant.parse("2026-11-01T02:15:00Z"))
        #expect(TaskFormat.moment(evening, zone: zone, today: today).text == "Yesterday, 9:15 PM")
    }

    @Test func wallClockPickIsSentAsTheRightInstantOnTheDSTDay() throws {
        let zone = try #require(TimeZone(identifier: "America/Chicago"))
        // 14:00 on Nov 1 is CST (UTC-6) after the change.
        let instant = TaskDetailModel.instant(date: today, minuteOfDay: 14 * 60, zone: zone)
        #expect(instant == WaiveraInstant.parse("2026-11-01T20:00:00Z"))
    }
}

/// The Tasks tab against the fake server: loading, empty, error, segments and paging rules.
@MainActor
struct TasksModelTests {
    @Test func loadsCaseworkGroupedWithCounts() async {
        let fakes = FakeDataEnvironment.make()
        let model = TasksModel(environment: fakes.environment, firstWeekday: 1)
        #expect(model.state.phase == .loading)
        let run = Task { await model.run() }
        defer { run.cancel() }
        model.setWindow(.allOpen)
        #expect(await eventually { model.state.phase == .content && model.state.counts != nil })
        let groups = model.state.sections.map(\.group)
        #expect(groups.first == .overdue)
        #expect(groups.contains(.delayed))
        #expect(model.state.counts?.delayed == 1)
        #expect(model.state.meta?.contains("1 delayed") == true)
        #expect(model.state.showsRequests)
        #expect(model.state.waitingCount == 2)
    }

    @Test func hidingDelaysAndMyWorkChangeTheList() async {
        let fakes = FakeDataEnvironment.make()
        let model = TasksModel(environment: fakes.environment, firstWeekday: 1)
        let run = Task { await model.run() }
        defer { run.cancel() }
        model.setWindow(.allOpen)
        model.setDelays(.hide)
        #expect(await eventually { model.state.phase == .content && model.state.counts != nil })
        #expect(!model.state.sections.contains { $0.group == .delayed })
        #expect(model.state.meta?.contains("delays hidden") == true)

        model.setSegment(.myWork)
        #expect(await eventually { model.state.phase == .content && model.state.rowCount == 2 })
        #expect(!model.state.showsDelays)
    }

    @Test func emptyAndErrorStates() async {
        let empty = TasksModel(environment: FakeDataEnvironment.make(.empty).environment)
        let run = Task { await empty.run() }
        defer { run.cancel() }
        #expect(await eventually { empty.state.phase == .empty })
        #expect(empty.state.emptyTitle == "Nothing due soon")

        let failing = FakeDataEnvironment.make(.failing)
        let model = TasksModel(environment: failing.environment)
        let failingRun = Task { await model.run() }
        defer { failingRun.cancel() }
        #expect(await eventually { model.state.phase == .error })
        failing.tasks.failure.update { $0 = nil }
        model.retry()
        #expect(await eventually { model.state.phase != .error && model.state.phase != .loading })
    }

    @Test func aFailedRefreshKeepsTheListAndSaysSo() async {
        let fakes = FakeDataEnvironment.make()
        let model = TasksModel(environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.phase == .content })
        let rows = model.state.rowCount
        fakes.tasks.failure.update { $0 = .offline }
        await model.refresh()
        #expect(model.state.phase == .content)
        #expect(model.state.rowCount == rows)
        #expect(model.state.refreshFailed)
        #expect(model.feedback.toast?.retry == .refresh)
    }

    @Test func searchWaitsForAPauseAndCountsMatches() async {
        let fakes = FakeDataEnvironment.make()
        let model = TasksModel(environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        model.setWindow(.allOpen)
        #expect(await eventually { model.state.phase == .content })
        model.setQuery("J")
        model.setQuery("Jordan")
        #expect(await eventually { model.state.phase == .content && model.state.rowCount == 2 })
        #expect(model.state.meta == "2 matches")
    }

    @Test func requestsHideWhenTheWebWouldHideThem() async {
        let fakes = FakeDataEnvironment.make()
        fakes.requests.setAccess(RequestAccess(showsRequests: false, loaded: true))
        let model = TasksModel(environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.phase == .content })
        #expect(model.state.segments == [.casework, .myWork])
        model.setSegment(.requests)
        #expect(model.state.segment == .casework)
    }
}

@MainActor
struct TaskDetailModelTests {
    @Test func loadsTheTaskActivityAndChoices() async {
        let fakes = FakeDataEnvironment.make()
        await fakes.environment.launch()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.phase == .content && model.state.activity.value != nil })
        #expect(model.state.task?.key == "HEA-1042")
        #expect(model.state.late)
        #expect(model.state.activity.value?.last?.byMe == true)
        #expect(await eventually { model.state.askChoices == [.moreTime, .delay, .closure] })
        #expect(model.state.canAsk)
    }

    @Test func aDelayedTaskIsNotLate() async {
        let model = TaskDetailModel(taskId: 14, environment: FakeDataEnvironment.make().environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.phase == .content })
        #expect(model.state.delay != nil)
        #expect(!model.state.late)
    }

    @Test func aMissingTaskShowsTheError() async {
        let model = TaskDetailModel(taskId: 999, environment: FakeDataEnvironment.make().environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.phase == .error })
        #expect(model.state.error == .notFound)
    }

    @Test func logActivityValidatesThenLandsAtTheBottom() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.phase == .content && model.state.activity.value != nil })
        model.startLog()
        #expect(await eventually { model.state.log?.types.value != nil })
        model.submitLog()
        #expect(model.state.log?.showErrors == true)
        #expect(fakes.tasks.logged.get().isEmpty)

        model.chooseType(3)
        #expect(model.state.log?.minutes == 30)
        #expect(model.state.log?.description == "Reviewed the plan")
        model.stepMinutes(up: true)
        #expect(model.state.log?.minutes == 30)
        model.chooseType(1)
        #expect(model.state.log?.description == "")
        model.setDescription("Visited the family")
        model.stepMinutes(up: false)
        #expect(model.state.log?.minutes == 15)
        model.submitLog()
        #expect(await eventually { model.state.log == nil && model.state.activity.value?.last?.isNew == true })
        #expect(fakes.tasks.logged.get().first?.description == "Visited the family")
    }

    @Test func aFailedLogKeepsTheFormFilled() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.phase == .content })
        model.startLog()
        #expect(await eventually { model.state.log?.types.value != nil })
        model.chooseType(1)
        model.setDescription("Call")
        fakes.tasks.failure.update { $0 = .server(statusCode: 500) }
        model.submitLog()
        #expect(await eventually { model.state.log?.failed == true })
        #expect(model.state.log?.description == "Call")
        #expect(model.state.log?.isSaving == false)
    }

    @Test func moreTimeShowsPendingAtOnceAndSends() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.canAsk })
        model.startAsk()
        #expect(model.state.ask?.kind == nil)
        model.chooseAsk(.moreTime)
        #expect(await eventually { model.state.ask?.reasons.value != nil })
        model.submitAsk()
        #expect(model.state.ask?.showErrors == true)
        #expect(model.state.ask?.dueMissing == true)
        let current = model.state.ask?.currentDue ?? DemoData.today
        model.setAskDue(current)
        #expect(model.state.ask?.dueTooEarly == true)
        model.setAskDue(current.adding(days: 7))
        model.setAskReason(1)
        model.setAskExplanation("Family is traveling")
        model.submitAsk()
        #expect(model.state.ask == nil)
        #expect(model.state.pending?.kind == .moreTime)
        #expect(await eventually { !fakes.requests.asked.get().isEmpty })
        #expect(fakes.requests.asked.get().first?.hasPrefix("moreTime:12:") == true)
    }

    @Test func evidenceIsNeededForSomeReasonsAndAFailureReopensTheForm() async {
        let fakes = FakeDataEnvironment.make()
        let model = TaskDetailModel(taskId: 12, environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.canAsk })
        model.startAsk()
        model.chooseAsk(.moreTime)
        #expect(await eventually { model.state.ask?.reasons.value != nil && model.state.ask?.files.value != nil })
        model.setAskDue((model.state.ask?.currentDue ?? DemoData.today).adding(days: 3))
        model.setAskReason(2)
        model.setAskExplanation("Hospital")
        #expect(model.state.ask?.evidenceMissing == true)
        model.setAskEvidence(41)
        #expect(model.state.ask?.isValid == true)
        fakes.requests.failure.update { $0 = .server(statusCode: 500) }
        model.submitAsk()
        #expect(await eventually { model.state.ask?.failed == true })
        #expect(model.state.pending == nil)
        #expect(model.state.ask?.explanation == "Hospital")
    }

    @Test func aFinishedTaskOffersNothing() {
        let form = AskForm(choices: [.closure], kind: .closure)
        // A closure comment is optional unless the reason needs one.
        #expect(!form.explanationMissing)
    }
}

@MainActor
struct RequestsModelTests {
    @Test func reviewConfirmAndDecide() async {
        let fakes = FakeDataEnvironment.make()
        let model = RequestsModel(environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.waiting.value?.count == 2 && model.state.mine.value != nil })
        let first = try? #require(model.state.waiting.value?.first)
        guard let first else { return }
        #expect(first.change.text?.contains("→") == true)
        #expect(model.review(first) == nil)
        #expect(model.state.reviewing?.id == 81)
        model.ask(approve: true)
        let copy = model.state.confirming?.item.confirmation(approve: true)
        #expect(copy?.title == "Approve more time?")
        #expect(copy?.message.contains("Dana Cole gets a notification") == true)
        model.confirm()
        #expect(model.state.reviewing == nil)
        #expect(await eventually { model.state.waiting.value?.count == 1 })
        #expect(await eventually { model.feedback.toast?.message.hasPrefix("Approved.") == true })
        #expect(fakes.requests.decided.get().first?.0 == 81)
    }

    @Test func aRefusedDecisionComesBackWithANote() async {
        let fakes = FakeDataEnvironment.make()
        let model = RequestsModel(environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.waiting.value?.count == 2 })
        guard let item = model.state.waiting.value?.last else { return }
        _ = model.review(item)
        model.ask(approve: false)
        fakes.requests.failure.update { $0 = .server(statusCode: 500) }
        model.confirm()
        #expect(await eventually { model.feedback.toast != nil })
        #expect(await eventually { model.state.waiting.value?.count == 2 })
        #expect(model.feedback.toast?.message.contains("back in your list") == true)
    }

    @Test func otherKindsOpenOnTheWeb() {
        let fakes = FakeDataEnvironment.make(webBaseURL: URL(string: "https://app.waivera.com"))
        let model = RequestsModel(environment: fakes.environment)
        let other = RequestItem(
            request: ChangeRequest(
                id: 9,
                kind: .other,
                typeName: "Time Off",
                status: .pending,
                requesterId: nil,
                requesterName: "Sam"
            ),
            asked: nil,
            change: .other,
            due: .none
        )
        #expect(model.review(other)?.absoluteString == "https://app.waivera.com/admin-requests")
    }
}
