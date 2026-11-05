import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TasksFeature

/// Mirrors Android `TaskReviewViewModelTest`: the chain's steps in the web's order, each answer,
/// and the refusals.
@MainActor
struct TaskReviewModelTests {
    @MainActor
    private final class Harness {
        let fakes = FakeDataEnvironment.make()
        let model: TaskReviewModel
        var effects: [ReviewEffect] = []

        init() {
            model = TaskReviewModel(taskId: 15, environment: fakes.environment)
            model.onEffect = { [unowned self] in self.effects.append($0) }
        }

        var today: CalendarDate { model.today }

        func task(dueIn days: Int = 3, client: Bool = true, plan: PlanDates? = nil) -> TaskDetail {
            TaskDetail(
                id: 15,
                key: "HEA-1050",
                title: "Plan of care signature",
                state: .inReview,
                due: today.adding(days: days),
                webPath: "/tasks/1050",
                isClientTask: client,
                review: TaskReviewAccess(canApprove: true, canApproveAll: true, remainingStages: 2, canReject: true),
                planDates: plan
            )
        }
    }

    private static let planRequirement = StageRequirement(
        actionId: 7,
        key: "plan",
        actionType: StageRequirement.planDates,
        title: "New plan dates",
        description: nil,
        fields: [
            dateField(StageRequirement.planStart, "Start"),
            dateField(StageRequirement.planEnd, "End"),
        ]
    )

    private static func dateField(_ key: String, _ label: String) -> RequirementField {
        RequirementField(key: key, label: label, type: .date, required: true, defaultValue: nil)
    }

    @Test func approvingOneStageSendsOnceAndReloads() async {
        let harness = Harness()
        harness.model.start(.approve, task: harness.task())
        #expect(await eventually { harness.effects.count == 2 })
        #expect(harness.effects == [.done(.approve, completed: false), .reload])
        #expect(harness.fakes.review.sent.get().count == 1)
        #expect(harness.model.state == ReviewState())
    }

    @Test func approveAsksThisStepOrAllAndThisStepSendsOneStage() async {
        let harness = Harness()
        harness.model.askScope(.approve, task: harness.task())
        #expect(harness.model.state.step == .chooseScope(stages: 2, submit: false))
        #expect(harness.fakes.review.sent.get().isEmpty)
        harness.model.chooseScope(all: false)
        #expect(await eventually { harness.effects.first == .done(.approve, completed: false) })
        #expect(harness.fakes.review.sent.get().first?.plan.mode == .currentStage)
    }

    /// Picking "all" in the scope sheet is the confirmation: no second "are you sure".
    @Test func choosingAllSkipsTheSecondConfirmation() async {
        let harness = Harness()
        harness.model.askScope(.submit, task: harness.task())
        #expect(harness.model.state.step == .chooseScope(stages: 2, submit: true))
        harness.model.chooseScope(all: true)
        #expect(await eventually { harness.effects.first == .done(.submitAll, completed: true) })
        #expect(harness.fakes.review.sent.get().first?.plan.mode == .allRemaining)
    }

    @Test func approveAllConfirmsThenChecksDraftsBeforeSending() async {
        let harness = Harness()
        harness.fakes.review.drafts.update { $0 = [FormDraft(id: 1, name: "Intake form")] }
        harness.model.start(.approveAll, task: harness.task())
        #expect(await eventually { harness.model.state.step == .confirmAll(stages: 2, submit: false) })
        // Nothing is sent before each step is answered.
        #expect(harness.fakes.review.sent.get().isEmpty)
        harness.model.confirmAll()
        #expect(await eventually { harness.model.state.step == .drafts(["Intake form"]) })
        harness.model.discardDrafts()
        #expect(await eventually { harness.effects.first == .done(.approveAll, completed: true) })
        let send = harness.fakes.review.sent.get().first
        #expect(send?.plan.mode == .allRemaining)
        #expect(send?.discardDrafts == true)
    }

    @Test func approveAllTheServerNoLongerAllowsStopsAndReloads() async {
        let harness = Harness()
        harness.fakes.review.plans.update {
            $0[.allRemaining] = ApprovalPlan(mode: .allRemaining, willComplete: true, canApproveAll: false)
        }
        harness.model.start(.approveAll, task: harness.task())
        #expect(await eventually { harness.effects == [.cantApproveAll, .reload] })
        #expect(harness.fakes.review.sent.get().isEmpty)
    }

    @Test func aReopenedTaskAsksWhichDriveSection() async {
        let harness = Harness()
        let previous = harness.today.adding(days: -40)
        harness.fakes.review.plans.update {
            $0[.currentStage] = ApprovalPlan(mode: .currentStage, willComplete: true, previousFiling: previous)
        }
        harness.model.start(.approve, task: harness.task())
        #expect(await eventually { harness.model.state.step == .driveSection(previous: previous, useOriginal: true) })
        harness.model.chooseDrive(original: false)
        harness.model.confirmDrive()
        #expect(await eventually { harness.effects.first == .done(.approve, completed: true) })
        #expect(harness.fakes.review.sent.get().first?.useOriginalSection == false)
    }

    @Test func anEmployeeTaskThatCompletesSavesAPlainCloseFirst() async {
        let harness = Harness()
        harness.model.start(.approveAll, task: harness.task(client: false))
        #expect(await eventually { harness.model.state.step != nil })
        harness.model.confirmAll()
        #expect(await eventually { harness.effects.first == .done(.approveAll, completed: true) })
        let choices = harness.fakes.review.closureChoices.get()
        #expect(choices.count == 1 && choices.first?.merge == nil && choices.first?.nextExpiration == nil)
    }

    @Test func requirementWarningsNeedASecondTapAndAChangeAsksAgain() async {
        let harness = Harness()
        let lastEnd = harness.today.adding(days: -1)
        harness.fakes.review.plans.update {
            $0[.currentStage] = ApprovalPlan(
                mode: .currentStage,
                willComplete: false,
                requirements: [Self.planRequirement]
            )
        }
        harness.fakes.review.outcomes.update { $0 = [.requirementsChanged([Self.planRequirement], version: "r2")] }
        harness.model.start(.approve, task: harness.task(plan: PlanDates(start: nil, end: lastEnd)))
        #expect(await eventually { if case .requirements = harness.model.state.step { true } else { false } })

        harness.model.submitRequirements()
        guard case .requirements(let empty) = harness.model.state.step else { return #expect(Bool(false)) }
        #expect(empty.errors[7]?[StageRequirement.planStart]?.kind == .required)

        // An end that isn't a year after the start warns; the second tap goes ahead.
        let start = harness.today.isoString
        harness.model.setRequirement(actionId: 7, key: StageRequirement.planStart, value: start)
        let end = harness.today.adding(days: 30).isoString
        harness.model.setRequirement(actionId: 7, key: StageRequirement.planEnd, value: end)
        harness.model.submitRequirements()
        guard case .requirements(let warned) = harness.model.state.step else { return #expect(Bool(false)) }
        #expect(warned.confirmWarnings && warned.hasWarnings)
        #expect(harness.fakes.review.sent.get().isEmpty)
        harness.model.submitRequirements()

        // The server changed what the stage needs: the plan is fetched again and asked with a new key.
        #expect(await eventually {
            if case .requirements(let form) = harness.model.state.step { form.changed } else { false }
        })
        // What was typed stays where the field is still asked.
        guard case .requirements(let again) = harness.model.state.step else { return #expect(Bool(false)) }
        #expect(again.values[7]?[StageRequirement.planStart] == start)
        let sends = harness.fakes.review.sent.get()
        #expect(sends.count == 1)
        #expect(sends.first?.answers[7]?[StageRequirement.planStart] == start)
        #expect(sends.first?.acknowledgeWarnings == false)
    }

    @Test func aRefusalForAnswersThatAFreshPlanNoLongerAsksStopsInsteadOfLooping() async {
        let harness = Harness()
        harness.fakes.review.outcomes.update { $0 = [.requirementsChanged([], version: "r2")] }
        harness.model.start(.approve, task: harness.task())
        #expect(await eventually { harness.effects == [.changed, .reload] })
        #expect(harness.fakes.review.sent.get().count == 1)
    }

    @Test func aLostAnswerWithNoSheetOpenReloadsTheTask() async {
        let harness = Harness()
        harness.fakes.review.outcomes.update { $0 = [nil] }
        harness.model.start(.approveAll, task: harness.task())
        #expect(await eventually { harness.model.state.step != nil })
        harness.model.confirmAll()
        #expect(await eventually { harness.effects == [.failed, .reload] })
    }

    @Test func aRelatedWarningCanBeAcknowledgedButABlockerCannot() async {
        let related = RelatedTask(id: 4, key: "HEA-88", title: "Intake", statusName: nil, relationship: nil)
        let harness = Harness()
        harness.fakes.review.outcomes.update { $0 = [.needsAcknowledgement([related])] }
        harness.model.start(.approve, task: harness.task())
        let warning = ReviewStep.related(blocked: false, tasks: [related], isSaving: false)
        #expect(await eventually { harness.model.state.step == warning })
        harness.model.completeAnyway()
        #expect(await eventually { harness.effects.first == .done(.approve, completed: false) })
        #expect(harness.fakes.review.sent.get().last?.acknowledgeWarnings == true)

        let blocked = Harness()
        blocked.fakes.review.outcomes.update { $0 = [.blocked([related])] }
        blocked.model.start(.approve, task: blocked.task())
        let blocker = ReviewStep.related(blocked: true, tasks: [related], isSaving: false)
        #expect(await eventually { blocked.model.state.step == blocker })
        blocked.model.completeAnyway()
        #expect(blocked.fakes.review.sent.get().count == 1)
        blocked.model.openRelated(4)
        #expect(blocked.effects == [.openTask(taskId: 4)])
        #expect(blocked.model.state == ReviewState())
    }

    @Test func aStaleTaskOrAFailedLoadStopsWithAMessage() async {
        let stale = Harness()
        stale.fakes.review.outcomes.update { $0 = [.stale] }
        stale.model.start(.approve, task: stale.task())
        #expect(await eventually { stale.effects == [.changed, .reload] })

        let failing = Harness()
        failing.fakes.review.plans.update { $0 = [:] }
        failing.model.start(.approve, task: failing.task())
        #expect(await eventually { failing.effects == [.failed] })
        #expect(failing.model.state == ReviewState())
    }

    @Test func aLateTaskAsksWhyFirstAndThenApproves() async {
        let harness = Harness()
        harness.fakes.review.late.update {
            $0 = LateContext(canSubmit: true, canReview: false, reviewedByMe: false, satisfied: false)
        }
        harness.model.start(.approve, task: harness.task(dueIn: -3))
        #expect(await eventually {
            if case .lateReason(let form) = harness.model.state.step { form.reasons.value != nil } else { false }
        })
        // A reason's preset fills the explanation until something is typed.
        harness.model.setLateReason(1)
        guard case .lateReason(let picked) = harness.model.state.step else { return #expect(Bool(false)) }
        #expect(picked.explanation == "Participant was unavailable.")
        #expect(picked.evidenceMissing)
        harness.model.submitLate()
        guard case .lateReason(let refused) = harness.model.state.step else { return #expect(Bool(false)) }
        #expect(refused.showErrors)
        #expect(harness.fakes.review.justified.get().isEmpty)

        harness.model.setLateReason(2)
        harness.model.setLateExplanation("Waiting on the county's records.")
        harness.model.submitLate()
        #expect(await eventually { harness.effects.contains(.done(.approve, completed: false)) })
        #expect(harness.fakes.review.justified.get().first?.reasonId == 2)
        #expect(harness.fakes.review.justified.get().first?.explanation == "Waiting on the county's records.")
        #expect(harness.effects.first == .reload)
    }

    @Test func aLateTaskOnlyTheAssigneeCanExplainStops() async {
        let harness = Harness()
        harness.fakes.review.late.update {
            $0 = LateContext(canSubmit: false, canReview: true, reviewedByMe: false, satisfied: false)
        }
        harness.model.start(.approve, task: harness.task(dueIn: -1))
        #expect(await eventually { harness.effects == [.lateNeedsAssignee] })
    }

    @Test func aReviewerAgreesWithTheLateReasonThenApproves() async {
        let harness = Harness()
        let reason = LateJustification(id: 31, reasonId: 2, reasonName: nil, explanation: "Records were late.")
        harness.fakes.review.late.update {
            $0 = LateContext(
                canSubmit: false,
                canReview: true,
                reviewedByMe: false,
                satisfied: true,
                justification: reason
            )
        }
        harness.model.start(.approve, task: harness.task(dueIn: -2))
        #expect(await eventually { if case .lateReview = harness.model.state.step { true } else { false } })
        harness.model.setLateNote("Confirmed with the county.")
        harness.model.agreeLate()
        #expect(await eventually { harness.effects.contains(.done(.approve, completed: false)) })
        #expect(harness.fakes.review.agreed.get().first?.justificationId == 31)
        #expect(harness.fakes.review.agreed.get().first?.note == "Confirmed with the county.")
    }

    @Test func aTaskNotYetDueSkipsTheLateCheck() async {
        let harness = Harness()
        harness.fakes.review.late.update { $0 = nil }
        harness.model.start(.approve, task: harness.task(dueIn: 1))
        #expect(await eventually { harness.effects.first == .done(.approve, completed: false) })
    }

    @Test func rejectingPicksTheOnlyChoiceAndSendsBack() async {
        let harness = Harness()
        harness.model.startReject()
        #expect(await eventually {
            if case .sendBack(let form) = harness.model.state.step { form.approvalId == 11 } else { false }
        })
        harness.model.submitSendBack()
        guard case .sendBack(let empty) = harness.model.state.step else { return #expect(Bool(false)) }
        #expect(empty.showErrors)
        harness.model.setFeedback("Missing the guardian's signature.")
        harness.model.setMinutes("1 5a")
        harness.model.submitSendBack()
        #expect(await eventually { harness.effects == [.sentBack, .reload] })
        #expect(harness.fakes.review.sentBack.get().first?.minutes == 15)
        #expect(harness.fakes.review.sentBack.get().first?.feedback == "Missing the guardian's signature.")
    }

    @Test func closingASheetDropsAnAnswerThatLandsLater() async {
        let harness = Harness()
        harness.model.start(.approveAll, task: harness.task())
        #expect(await eventually { harness.model.state.step != nil })
        harness.model.dismiss()
        harness.model.confirmAll()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(harness.fakes.review.sent.get().isEmpty)
        #expect(harness.effects.isEmpty)
    }
}
