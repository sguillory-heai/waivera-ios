import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraData

@Suite("Task review mapping")
struct ReviewMappingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try WaiveraJSON.decoder().decode(type, from: Data(json.utf8))
    }

    @Test func planKeepsTheServersModeVersionsAndDateOnlyFields() throws {
        let dto = try decode(
            ApprovalRequirementsResponse.self,
            #"""
            {"approvalMode":"allremaining","willCompleteTask":true,"previousDriveFilingDate":"2026-03-01",
             "requirementsVersion":"r9","workflowVersion":"w9","canApproveAllRemaining":true,"remainingStageCount":3,
             "requirements":[{"actionId":7,"requirementKey":"plan","actionType":"PARTICIPANT_PROFILE_CHANGE",
               "title":" New plan ","fields":[
                 {"key":"cpocDate","label":"Start","fieldType":"date","required":true,
                  "defaultValue":"2026-04-01T00:00:00"},
                 {"key":"proof","fieldType":"file"}]}]}
            """#
        )
        let plan = ReviewMapping.plan(dto, asked: .currentStage)
        #expect(plan.mode == .allRemaining)
        #expect(plan.willComplete && plan.canApproveAll && plan.remainingStages == 3)
        #expect(plan.previousFiling == CalendarDate(year: 2026, month: 3, day: 1))
        let requirement = try #require(plan.requirements.first)
        #expect(requirement.title == "New plan")
        #expect(requirement.isPlanDates)
        // A file field can't be answered on the phone, as on the web.
        #expect(!requirement.supported)
        #expect(requirement.fields.last?.label == "proof")
    }

    @Test func anUnknownModeFallsBackToTheOneAsked() throws {
        let dto = try decode(ApprovalRequirementsResponse.self, #"{"approvalMode":"Later"}"#)
        #expect(ReviewMapping.plan(dto, asked: .currentStage).mode == .currentStage)
    }

    @Test func refusalsBecomeTheirStep() throws {
        let blocked = try decode(
            ApprovalErrorResponse.self,
            #"""
            {"code":"TASK_COMPLETION_BLOCKED","completion":{"blockers":[
              {"sourceTaskId":4,"sourceTaskFriendlyId":88,"sourceTaskTitle":"Intake","organizationAbbreviation":"HEA",
               "relationshipName":"Depends on","sourceToTargetName":"Must finish first"}]}}
            """#
        )
        #expect(
            ReviewMapping.refusal(blocked)
                == .blocked([
                    RelatedTask(
                        id: 4,
                        key: "HEA-88",
                        title: "Intake",
                        statusName: nil,
                        relationship: "Must finish first"
                    )
                ])
        )
        let changed = try decode(
            ApprovalErrorResponse.self,
            #"{"code":"WORKFLOW_REQUIREMENTS_CHANGED","requirementsVersion":"r2","requirements":[]}"#
        )
        #expect(ReviewMapping.refusal(changed) == .requirementsChanged([], version: "r2"))
        let noList = try decode(ApprovalErrorResponse.self, #"{"code":"WORKFLOW_REQUIREMENTS_NOT_SATISFIED"}"#)
        #expect(ReviewMapping.refusal(noList) == .stale)
        #expect(ReviewMapping.refusal(nil) == .stale)
        let other = try decode(ApprovalErrorResponse.self, #"{"code":"WORKFLOW_VERSION_MISMATCH"}"#)
        #expect(ReviewMapping.refusal(other) == .stale)
    }

    @Test func bodySendsOnlyFilledAnswersAndTheOriginalSectionDate() {
        let requirement = StageRequirement(
            actionId: 7,
            key: "plan",
            actionType: StageRequirement.planDates,
            title: "Plan",
            description: nil,
            fields: []
        )
        let plan = ApprovalPlan(
            mode: .currentStage,
            willComplete: true,
            previousFiling: CalendarDate(year: 2026, month: 3, day: 1),
            requirementsVersion: "r1",
            workflowVersion: "w1",
            requirements: [requirement]
        )
        let send = ApprovalSend(
            plan: plan,
            idempotencyKey: "k",
            answers: [7: ["cpocDate": "2026-04-01", "cpocEndDate": " "]],
            acknowledgeWarnings: true,
            discardDrafts: true,
            useOriginalSection: true
        )
        let body = ReviewMapping.body(send)
        #expect(body.mode == "CurrentStage")
        #expect(body.requirementResponses.first?.values == ["cpocDate": "2026-04-01"])
        #expect(body.expectedPreviousDriveFilingDate == "2026-03-01")
        #expect(body.acknowledgeRelationshipWarnings && body.closeUnfinalizedDrafts)
    }

    @Test func lateReasonsFollowTheWebFilter() throws {
        let items = try decode(
            [ComplianceReasonResponse].self,
            #"""
            [{"id":1,"name":"Sick","isSystemCode":true,"canBeUsedForLateJustification":true,"presetExplanation":" "},
             {"id":2,"name":"Hidden","isSystemCode":true,"isHiddenFromUserSelection":true,
              "canBeUsedForLateJustification":true},
             {"id":3,"name":"Agency","isActive":true,"canBeUsedForLateJustification":true,"requiresEvidence":true,
              "presetExplanation":"Waiting on records."},
             {"id":4,"name":"Inactive","isActive":false,"canBeUsedForLateJustification":true},
             {"id":5,"name":"Extension only","isActive":true}]
            """#
        )
        let reasons = ReviewMapping.lateReasons(items)
        #expect(reasons.map(\.id) == [1, 3])
        #expect(reasons[0].preset == nil)
        #expect(reasons[1].preset == "Waiting on records." && reasons[1].requiresEvidence)
    }
}
