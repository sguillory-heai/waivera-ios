import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ProfileFeature

private func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
}

/// Request time off (Android `TimeOffFormViewModelTest`): the web's bounds and checks.
struct TimeOffDraftsTests {
    private let chicago = TimeZone(identifier: "America/Chicago") ?? .gmt

    private func day(_ value: Int) -> CalendarDate {
        CalendarDate(year: 2026, month: 11, day: value) ?? CalendarDate(Date(), in: .gmt)
    }

    @Test func fullDaysAreSentAsUTCCalendarBounds() throws {
        var state = TimeOffFormState(today: day(2))
        state.typeId = 1
        state.firstDay = day(24)
        state.lastDay = day(26)
        let draft = try #require(TimeOffDrafts.draft(state, zone: chicago))
        #expect(iso(draft.start) == "2026-11-24T00:00:00.000Z")
        #expect(iso(draft.end) == "2026-11-26T23:59:59.999Z")
        #expect(!draft.partialDay)
    }

    /// Sunday 1 November 2026: Chicago falls back from CDT to CST at 2 AM.
    @Test func partialDaysAreReadInTheSavedZoneAcrossTheDSTChange() throws {
        var state = TimeOffFormState(today: day(1))
        state.typeId = 1
        state.partialDay = true
        state.day = day(1)
        state.from = 9 * 60
        state.to = 11 * 60
        let draft = try #require(TimeOffDrafts.draft(state, zone: chicago))
        // 9 AM CST is 15:00 UTC; before the change it would have been 14:00.
        #expect(iso(draft.start) == "2026-11-01T15:00:00.000Z")
        #expect(TimeOffDrafts.issue(state, zone: chicago) == nil)
        // Midnight to 8 AM that day is nine real hours, over the web's eight-hour limit.
        state.from = 0
        state.to = 8 * 60
        #expect(TimeOffDrafts.issue(state, zone: chicago) == .tooLong)
        state.from = 9 * 60
        state.to = 9 * 60 + 15
        #expect(TimeOffDrafts.issue(state, zone: chicago) == .tooShort)
    }

    @Test func aLastDayBeforeTheFirstIsAnIssueAndPastDaysAreNoted() {
        var state = TimeOffFormState(today: day(10))
        state.firstDay = day(8)
        state.lastDay = day(7)
        #expect(TimeOffDrafts.issue(state, zone: chicago) == .endBeforeStart)
        #expect(TimeOffDrafts.past(state, today: day(10)))
    }
}

@MainActor
struct TimeOffFormModelTests {
    private func model() -> (TimeOffFormModel, FakeDataEnvironment) {
        let fakes = FakeDataEnvironment.make()
        return (TimeOffFormModel(environment: fakes.environment), fakes)
    }

    private func fill(_ form: TimeOffFormModel) {
        form.pickType(1)
        let start = form.state.today.adding(days: 7)
        form.pickFirstDay(start)
        form.pickLastDay(start.adding(days: 1))
    }

    @Test func aCheckedRequestSendsAndShowsAsPending() async {
        let (form, fakes) = model()
        form.reset()
        await eventually { form.state.types != .loading }
        fill(form)
        #expect(form.state.check == .checking)
        await eventually { form.state.canSend }
        var sent: TimeOffEntry?
        form.onSent = { sent = $0 }
        form.send()
        await eventually { sent != nil }
        #expect(sent?.status == .pending)
        #expect(sent?.leaveType == "Vacation")
        #expect(fakes.requests.leaveSends.get().first?.leaveTypeId == 1)
    }

    @Test func aRefusalUsesTheAppsWordsAndClearsOnTheNextChange() async {
        let (form, fakes) = model()
        form.reset()
        await eventually { form.state.types != .loading }
        fill(form)
        await eventually { form.state.canSend }
        fakes.requests.leaveRefusal.update { $0 = .notEnoughBalance }
        form.send()
        await eventually { form.state.failure != nil }
        #expect(form.state.failure?.problem == .notEnoughBalance)
        form.setNote("Family trip")
        #expect(form.state.failure == nil)
    }

    @Test func aBalanceBelowZeroOrABlockedDayCannotBeSent() async {
        let (form, fakes) = model()
        form.reset()
        await eventually { form.state.types != .loading }
        fakes.requests.nextPreview.update {
            $0 = LeavePreview(
                requestedMinutes: 960,
                tracksBalance: true,
                beforeMinutes: 600,
                afterMinutes: -360,
                block: nil,
                impact: nil
            )
        }
        fill(form)
        await eventually { form.state.check != .checking }
        #expect(form.state.overBalance)
        #expect(!form.state.canSend)
        fakes.requests.nextPreview.update {
            $0 = LeavePreview(
                requestedMinutes: 0,
                tracksBalance: false,
                beforeMinutes: nil,
                afterMinutes: nil,
                block: .weekend,
                impact: nil
            )
        }
        form.retryCheck()
        await eventually { form.state.check != .checking }
        #expect(!form.state.canSend)
    }
}
