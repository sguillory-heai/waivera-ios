import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraData

/// Every admin request type reviewed on the phone, as the web reviews it (Android
/// `ApprovalMappingTest` and `LiveRequestRepositoryTest`).
@Suite("Approvals")
struct ApprovalTests {
    private let me = CurrentUser(id: "u-alex", firebaseUid: "fb-alex")

    @Test func timeOffDatesAreUTCCalendarDaysAndTheReviewIsCompared() throws {
        let saved = #"{"overdueCount":1,"dueDuringLeaveCount":2,"warnings":[{"code":"FUTURE_TASK_REVIEW"}]}"#
        let current = #"{"overdueCount":1,"dueDuringLeaveCount":2,"warnings":[{"code":"SHORT_NOTICE_VACATION"}]}"#
        let review = ApprovalMapping.timeOff(
            TimeOffDetailsResponse(
                timeOffStartDate: "2026-11-24T00:00:00",
                timeOffEndDate: "2026-11-26T00:00:00Z",
                typeOfLeave: " Vacation ",
                typeOfLeaveId: 2,
                requestType: "FULL_DAY",
                durationMinutes: 1_440,
                intelligenceSnapshotJson: saved,
                currentIntelligenceJson: current,
                reviewRevision: 3,
                impactAcknowledgedRevision: 3,
                impactAcknowledgedAt: "2026-11-20T15:00:00Z"
            )
        )
        #expect(review.startDate == CalendarDate(year: 2026, month: 11, day: 24))
        #expect(review.endDate == CalendarDate(year: 2026, month: 11, day: 26))
        #expect(review.leaveType == "Vacation")
        #expect(!review.partialDay)
        #expect(review.impact == LeaveImpact(dueBefore: 1, dueDuring: 2, shortNotice: true))
        // A future-task note is not shown, so only the new short-notice warning counts as a change.
        #expect(review.impactChanged)
        #expect(review.acknowledged == true)
    }

    @Test func aReviewAcknowledgedForAnOlderRevisionIsNotAcknowledged() {
        let review = ApprovalMapping.timeOff(
            TimeOffDetailsResponse(
                intelligenceSnapshotJson: #"{"overdueCount":0}"#,
                reviewRevision: 4,
                impactAcknowledgedRevision: 3,
                impactAcknowledgedAt: "2026-11-20T15:00:00Z"
            )
        )
        #expect(review.acknowledged == false)
        #expect(!review.impactChanged)
        #expect(ApprovalMapping.timeOff(TimeOffDetailsResponse()).acknowledged == nil)
    }

    @Test func profileChangesMaskTheSSNAndSkipAnEmptyWaiverID() {
        let fields = ApprovalMapping.profile(
            ParticipantChangeResponse(
                newProfileChanegs: ParticipantProfileResponse(
                    firstName: "Maya",
                    mobileNumber: "5550107781",
                    waiverId: 0,
                    participantSsnLast4: "4321",
                    cpocDate: "2026-12-01T00:00:00"
                ),
                orignalProfile: ParticipantProfileResponse(
                    firstName: "Maya",
                    mobileNumber: "5550102299",
                    waiverId: 0,
                    participantSsnLast4: "1234",
                    cpocDate: "2026-11-01T00:00:00"
                )
            )
        )
        #expect(fields.map(\.field) == [.firstName, .mobile, .ssn, .cpocStart])
        #expect(fields.first { $0.field == .firstName }?.changed == false)
        let ssn = fields.first { $0.field == .ssn }
        #expect(ssn?.changed == true)
        #expect(ssn?.previous == "••••" && ssn?.requested == "••••")
        #expect(fields.first { $0.field == .cpocStart }?.requested == "2026-12-01")
    }

    @Test func trainingCreditsSayWhyTheyCannotBeDecided() {
        let own = ApprovalMapping.training(
            requestId: 9,
            TrainingCreditResponse(
                status: "Pending",
                revision: 2,
                canApprove: false,
                approvalBlockedReason: "You cannot approve your own training credit."
            )
        )
        #expect(own.blocked == .ownCredit)
        #expect(!own.decidable)
        let open = ApprovalMapping.training(
            requestId: 9,
            TrainingCreditResponse(status: "", revision: 2, canApprove: true, submittedByName: "Pat")
        )
        #expect(open.decidable)
        #expect(open.uploadedBy == nil)
        let web = ApprovalMapping.training(
            requestId: 9,
            TrainingCreditResponse(revision: 2, canApprove: true, standaloneCreditId: 40)
        )
        #expect(web.reviewOnWeb && !web.decidable)
    }

    private func make(_ items: String) async -> (LiveRequestsRepository, RoutingTransport) {
        let transport = RoutingTransport()
        await transport.set(
            "GET api/admin/request/pending-approvals",
            .json(#"{"data":{"items":["# + items + #"],"totalCount":1},"success":true}"#)
        )
        return (LiveRequestsRepository(api: makeAPI(transport), context: SessionContext(user: me)), transport)
    }

    @Test func eachKindIsDecidedOnItsOwnRoute() async throws {
        let (repository, transport) = await make(
            #"""
            {"id":11,"transactionType":"Time-Off Request","status":"PENDING","requesterId":"u-jo",
             "timeOffDetails":{"typeOfLeave":"Sick","typeOfLeaveId":3,"requestType":"FULL_DAY"}},
            {"id":12,"transactionType":"Profile Change Request","status":"PENDING"},
            {"id":13,"transactionType":"External Training Credit","status":"PENDING"}
            """#
        )
        try await repository.refreshWaiting()
        let list = try #require(await latest(repository.waiting()) ?? nil)
        #expect(list.map(\.kind) == [.timeOff, .profileChange, .trainingCredit])
        #expect(list[0].timeOff?.leaveTypeId == 3)

        await transport.set("POST api/TimeOff/approve-reject/11", .json(#"{"success":true}"#))
        try await repository.decide(list[0], approve: true)
        let timeOff = try #require(await transport.bodies("POST api/TimeOff/approve-reject/11").first)
        let body = try #require(String(data: timeOff, encoding: .utf8))
        #expect(body.contains(#""action":"approve""#) && body.contains("Approved via Admin Panel"))

        await transport.set("POST api/admin/request/approve-reject/12", .json(#"{"success":true}"#))
        try await repository.decide(list[1], approve: false)
        let profile = try #require(await transport.bodies("POST api/admin/request/approve-reject/12").first)
        #expect(String(data: profile, encoding: .utf8)?.contains(#""action":"reject""#) == true)

        // A training decision without the credit's revision never reaches the server.
        await #expect(throws: WaiveraError.self) { try await repository.decide(list[2], approve: true) }
        await transport.set("POST api/training/external/requests/13/decision", .json(#"{"success":true}"#))
        let reason = TrainingDecision(revision: 4, reason: " Blurry ")
        try await repository.decide(list[2], approve: false, training: reason)
        let training = try #require(await transport.bodies("POST api/training/external/requests/13/decision").first)
        let decision = try #require(String(data: training, encoding: .utf8))
        #expect(decision.contains(#""revision":4"#) && decision.contains(#""reason":"Blurry""#))
        #expect((await latest(repository.waiting()) ?? nil)?.isEmpty == true)
    }

    @Test func aReviewerWhoMayNotSeeBalancesGetsNone() async throws {
        let (repository, transport) = await make("")
        await transport.set("GET api/leave-management/employees/u-jo/balances", .status(403))
        #expect(try await repository.leaveBalance(employeeId: "u-jo", leaveTypeId: 3) == nil)
        await transport.set(
            "GET api/leave-management/employees/u-jo/balances",
            .json(#"{"data":{"balances":[{"id":3,"tracksBalance":true,"availableMinutes":600}]},"success":true}"#)
        )
        let balance = try await repository.leaveBalance(employeeId: "u-jo", leaveTypeId: 3)
        #expect(balance == LeaveBalance(leaveTypeId: 3, tracksBalance: true, availableMinutes: 600))
    }
}
