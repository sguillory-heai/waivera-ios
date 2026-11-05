import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TasksFeature

/// Reviewing time off, profile changes and training credit (Android `RequestsViewModelTest`).
struct RequestItemsTests {
    private let chicago = TimeZone(identifier: "America/Chicago") ?? .gmt
    private let today = CalendarDate(year: 2026, month: 10, day: 30) ?? DemoData.today

    private func partialDay(start: TimeInterval, end: TimeInterval) -> TimeOffReview {
        TimeOffReview(
            leaveType: "Sick",
            leaveTypeId: 3,
            partialDay: true,
            startDate: nil,
            endDate: nil,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end),
            minutes: 120,
            note: nil,
            impact: nil,
            impactChanged: false,
            acknowledged: nil
        )
    }

    /// Sunday 1 November 2026, 9:00 to 11:00 in Chicago, just after clocks fell back to CST.
    @Test func aPartialDayAcrossTheDSTChangeIsToldInTheLeaveZone() {
        // 15:00Z and 17:00Z: 9 AM and 11 AM CST (UTC-6), not CDT.
        let change = RequestItems.timeOff(
            partialDay(start: 1_793_545_200, end: 1_793_552_400),
            cancellation: false,
            zone: chicago,
            today: today
        )
        guard case .timeOff(let time) = change else {
            Issue.record("expected time off")
            return
        }
        #expect(time.times == TimeSpan(start: "9:00 AM", end: "11:00 AM"))
        #expect(time.dates.end == nil)
        #expect(time.dates.start.contains("Nov 1"))
    }

    @Test func aPendingRequestAlreadyHoldsItsMinutes() {
        let time = partialDay(start: 0, end: 7_200)
        let balance = LeaveBalance(leaveTypeId: 3, tracksBalance: true, availableMinutes: 60)
        #expect(
            RequestItems.balance(balance, timeOff: time, cancellation: false) == BalanceChange(before: 180, after: 60)
        )
        #expect(
            RequestItems.balance(balance, timeOff: time, cancellation: true) == BalanceChange(before: 60, after: 180)
        )
        let untracked = LeaveBalance(leaveTypeId: 3, tracksBalance: false, availableMinutes: 0)
        #expect(RequestItems.balance(untracked, timeOff: time, cancellation: false) == nil)
    }

    @Test func hoursReadAsTheWebShowsThem() {
        #expect(RequestItems.hours(minutes: 60) == "1 hr")
        #expect(RequestItems.hours(minutes: 90) == "1.5 hrs")
        #expect(RequestItems.hours(minutes: -195) == "-3.25 hrs")
        #expect(RequestItems.hours(minutes: 0) == "0 hrs")
    }

    @Test func profileDatesReadInFullAndChangedFieldsLead() {
        let change = RequestItems.profile(
            [
                ProfileField(field: .dateOfBirth, previous: "1990-04-02", requested: "1990-04-03", changed: true),
                ProfileField(field: .firstName, previous: "Maya", requested: "Maya", changed: false),
            ],
            today: today
        )
        guard case .profile(let changed, let unchanged) = change else {
            Issue.record("expected a profile change")
            return
        }
        #expect(changed.map(\.field) == [.dateOfBirth])
        #expect(changed.first?.requested?.contains("1990") == true)
        #expect(unchanged.map(\.field) == [.firstName])
    }
}

@MainActor
struct ApprovalReviewModelTests {
    @Test func aTrainingRejectionNeedsAReasonAndSendsTheRevision() async {
        let fakes = FakeDataEnvironment.make()
        fakes.requests.setWaiting(FakeRequestsRepository.demoApprovals())
        let model = RequestsModel(environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.waiting.value?.count == 3 })
        guard let credit = model.state.waiting.value?.first(where: { $0.request.kind == .trainingCredit }) else {
            Issue.record("expected a training credit")
            return
        }
        #expect(model.review(credit) == nil)
        #expect(await eventually { model.state.training.value != nil })
        model.ask(approve: false)
        #expect(!model.state.canConfirm)
        model.setReason("   ")
        #expect(!model.state.canConfirm)
        model.setReason("The date is missing.")
        #expect(model.state.canConfirm)
        model.confirm()
        #expect(await eventually { fakes.requests.decided.get().first?.0 == 85 })
    }

    @Test func timeOffLoadsTheRequestersBalance() async {
        let fakes = FakeDataEnvironment.make()
        fakes.requests.setWaiting(FakeRequestsRepository.demoApprovals())
        let model = RequestsModel(environment: fakes.environment)
        let run = Task { await model.run() }
        defer { run.cancel() }
        #expect(await eventually { model.state.waiting.value?.count == 3 })
        guard let leave = model.state.waiting.value?.first(where: { $0.request.kind == .timeOff }) else {
            Issue.record("expected time off")
            return
        }
        _ = model.review(leave)
        // 40 hours left after this 24-hour request.
        #expect(await eventually { model.state.balance == .ready(BalanceChange(before: 3_840, after: 2_400)) })
        model.ask(approve: true)
        #expect(model.state.confirming?.item.confirmation(approve: true).title == "Approve time off?")
    }
}
