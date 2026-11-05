import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Where a running chain stands; it ends with the chain. Copies keep the chain's `id`, so an
/// answer that lands after the chain was closed or restarted is dropped.
struct ReviewChain: Equatable {
    let id = UUID()
    var action: ReviewAction
    var task: TaskDetail
    var lateChecked = false
    var plan: ApprovalPlan?
    var confirmedAll = false
    var draftsChecked = false
    var discardDrafts = false
    var useOriginal: Bool?
    var closurePrepared = false
    var answers: [Int: [String: String]]?
    var acknowledged = false
    /// The server changed what the stage needs; the refetched questions say so.
    var requirementsChanged = false
    /// What was typed before the server turned the answers away, kept where the fields still match.
    var keptAnswers: [Int: [String: String]] = [:]
    var idempotencyKey = UUID().uuidString.lowercased()
}

/// Submit, Approve and Reject (Android `TaskReviewViewModel`) with every step sprout_web's
/// `TaskPage.HandleApprove` runs, in the same order: the late reason (client tasks past due) and
/// its review, the "approve all" confirmation, unfinished forms, the Drive section of a reopened
/// task, the employee closure choice, the stage's own requirements, then the send and the
/// related-task answers. Each step is one sheet; finishing it moves the chain on, closing it
/// stops the chain.
@MainActor
@Observable
final class TaskReviewModel {
    /// Set only by this model and its extensions in the other Review files.
    var state = ReviewState()

    /// Results for the task screen: its message, a reload, or a file or task to open.
    @ObservationIgnored var onEffect: ((ReviewEffect) -> Void)?
    @ObservationIgnored let taskId: Int
    @ObservationIgnored let review: any TaskReviewRepository
    @ObservationIgnored let uploads: any TaskUploadsRepository
    @ObservationIgnored private let calendar: any CalendarRepository
    @ObservationIgnored private let clock: any WaiveraClock
    @ObservationIgnored let bag = TaskBag()
    @ObservationIgnored var chain: ReviewChain?
    @ObservationIgnored var preparing: Task<Void, Never>?

    init(taskId: Int, environment: DataEnvironment) {
        self.taskId = taskId
        review = environment.review
        uploads = environment.uploads
        calendar = environment.calendar
        clock = environment.clock
    }

    /// Today in the employee's saved zone.
    var today: CalendarDate { CalendarDate(clock.now, in: calendar.scheduleTimeZone().zone) }

    func start(_ action: ReviewAction, task: TaskDetail) {
        guard !state.busy else { return }
        chain = ReviewChain(action: action, task: task)
        state = ReviewState(step: nil, running: action)
        advance()
    }

    /// Closing any sheet stops the chain where it is; nothing was sent yet unless it says so.
    func dismiss() {
        guard !state.stepSaving else { return }
        if case .lateReason(let form) = state.step, let file = form.evidence { discardLater(file) }
        preparing?.cancel()
        chain = nil
        state = ReviewState()
    }

    // MARK: The chain

    func advance() {
        guard let current = chain else { return }
        bag.run { [weak self] in
            guard let self else { return }
            if self.needsLateCheck(current) {
                await self.checkLate(current)
            } else if let plan = current.plan {
                await self.afterPlan(current, plan)
            } else {
                await self.loadPlan(current)
            }
        }
    }

    func isCurrent(_ chain: ReviewChain) -> Bool { self.chain?.id == chain.id }

    /// sprout_web checks the late reason for client tasks past their (effective) due day only.
    private func needsLateCheck(_ chain: ReviewChain) -> Bool {
        guard !chain.lateChecked, chain.task.isClientTask, !chain.task.isFinished, let due = chain.task.due else {
            return false
        }
        // The server compares UTC days; checking when either day is past lets the server's answer decide.
        return today > due || CalendarDate(clock.now, in: .gmt) > due
    }

    private func checkLate(_ current: ReviewChain) async {
        let review = review
        let id = taskId
        let result = await attempt { try await review.lateContext(taskId: id) }
        guard isCurrent(current) else { return }
        guard case .success(let context) = result else { return fail() }
        var next = current
        next.lateChecked = true
        chain = next
        if !context.late, !context.satisfied {
            advance()
        } else if !context.satisfied, !context.canSubmit {
            stop(.lateNeedsAssignee)
        } else if !context.satisfied {
            openLateForm(context, due: current.task.due)
        } else if context.canReview, !context.reviewedByMe {
            show(.lateReview(LateCheck(context: context)))
        } else {
            advance()
        }
    }

    private func loadPlan(_ current: ReviewChain) async {
        let mode = current.action.mode
        let review = review
        let id = taskId
        let result = await attempt { try await review.plan(taskId: id, mode: mode) }
        guard isCurrent(current) else { return }
        guard case .success(let plan) = result else { return fail() }
        if plan.mode != mode || (mode == .allRemaining && !plan.canApproveAll) {
            stop(.cantApproveAll, reload: true)
        } else {
            var next = current
            next.plan = plan
            chain = next
            await afterPlan(next, plan)
        }
    }

    private func afterPlan(_ current: ReviewChain, _ plan: ApprovalPlan) async {
        if plan.mode == .allRemaining, !current.confirmedAll {
            show(.confirmAll(stages: plan.remainingStages, submit: current.action == .submitAll))
        } else if plan.willComplete, !current.draftsChecked {
            await checkDrafts(current)
        } else if plan.willComplete, let previous = plan.previousFiling, current.useOriginal == nil {
            show(.driveSection(previous: previous, useOriginal: true))
        } else if !current.task.isClientTask, plan.willComplete, !current.closurePrepared {
            await prepareClosure(current)
        } else if !plan.requirements.isEmpty, current.answers == nil {
            show(
                .requirements(
                    RequirementsForm(
                        requirements: plan.requirements,
                        values: Self.values(plan.requirements, keeping: current.keptAnswers),
                        changed: current.requirementsChanged
                    )
                )
            )
        } else if current.requirementsChanged, plan.requirements.isEmpty {
            // Refused for its answers, yet the fresh plan asks nothing: sending again would loop.
            stop(.changed, reload: true)
        } else {
            await send(current, plan)
        }
    }

    private func checkDrafts(_ current: ReviewChain) async {
        let review = review
        let id = taskId
        let result = await attempt { try await review.drafts(taskId: id) }
        guard isCurrent(current) else { return }
        guard case .success(let drafts) = result else { return fail() }
        var next = current
        next.draftsChecked = true
        chain = next
        if drafts.isEmpty {
            advance()
        } else {
            show(.drafts(drafts.map(\.name).filter { !$0.isEmpty }))
        }
    }

    private func prepareClosure(_ current: ReviewChain) async {
        let review = review
        let id = taskId
        let result = await attempt { try await review.employeeClosure(taskId: id) }
        guard isCurrent(current) else { return }
        guard case .success(let options) = result else { return fail() }
        if options.asks { return show(.closure(ClosureForm(options: options))) }
        // A plain close replaces any merge saved earlier, as the web does.
        let saved = await attempt { try await review.chooseClosure(taskId: id, merge: nil, nextExpiration: nil) }
        guard isCurrent(current) else { return }
        guard case .success = saved else { return fail() }
        var next = current
        next.closurePrepared = true
        chain = next
        advance()
    }

    private func send(_ current: ReviewChain, _ plan: ApprovalPlan) async {
        setSaving(true)
        let send = ApprovalSend(
            plan: plan,
            idempotencyKey: current.idempotencyKey,
            answers: current.answers ?? [:],
            acknowledgeWarnings: current.acknowledged,
            discardDrafts: current.discardDrafts,
            useOriginalSection: current.useOriginal == true
        )
        let review = review
        let id = taskId
        let result = await attempt { try await review.approve(taskId: id, send: send) }
        // An approval that went through is reported even if its sheet was closed meanwhile; a
        // newer chain started since keeps its own sheet.
        if case .success(.approved(let completed)) = result {
            guard isCurrent(current) else {
                onEffect?(.done(current.action, completed: completed))
                onEffect?(.reload)
                return
            }
            return stop(.done(current.action, completed: completed), reload: true)
        }
        guard isCurrent(current) else { return }
        switch result {
        case .failure where state.step == nil:
            // The server may have taken it before the answer was lost: show the task as it is now.
            stop(.failed, reload: true)
        case .failure:
            setSaving(false)
            failInSheet()
        case .success(.approved): break
        case .success(.blocked(let tasks)): show(.related(blocked: true, tasks: tasks, isSaving: false))
        case .success(.needsAcknowledgement(let tasks)): show(.related(blocked: false, tasks: tasks, isSaving: false))
        case .success(.requirementsChanged): requirementsChanged(current)
        case .success(.stale): stop(.changed, reload: true)
        }
    }

    /// The server's workflow version includes the requirements version, so the plan is fetched
    /// again for both before asking; resending with the old one would be refused the same way.
    private func requirementsChanged(_ current: ReviewChain) {
        var next = current
        next.plan = nil
        next.keptAnswers = current.answers ?? [:]
        next.answers = nil
        next.requirementsChanged = true
        next.idempotencyKey = UUID().uuidString.lowercased()
        chain = next
        advance()
    }

    // MARK: Helpers

    /// A confirmation closes as it is answered, as the web's do; the button shows the progress.
    func moveOn(_ edit: (inout ReviewChain) -> Void) {
        guard var current = chain else { return }
        edit(&current)
        chain = current
        switch state.step {
        case .confirmAll, .drafts, .driveSection: state.step = nil
        default: state.step = state.step?.withSaving(true)
        }
        advance()
    }

    func show(_ step: ReviewStep) { state.step = step }

    func stop(_ effect: ReviewEffect, reload: Bool = false) {
        chain = nil
        state = ReviewState()
        onEffect?(effect)
        if reload { onEffect?(.reload) }
    }

    /// A load failed: with a sheet open it says so there; otherwise the chain stops with a message.
    func fail() {
        if state.step == nil { stop(.failed) } else { failInSheet() }
    }

    private func failInSheet() {
        switch state.step {
        case .requirements: updateRequirements { $0.isSaving = false; $0.failed = true }
        case .closure: updateClosure { $0.isSaving = false; $0.failed = true }
        case .lateReason: updateLate { $0.isSaving = false; $0.failed = true }
        case .lateReview: updateLateCheck { $0.isSaving = false; $0.failed = true }
        // The confirmations have no room for an error, so they close and say it once.
        default: stop(.failed)
        }
    }

    private func setSaving(_ saving: Bool) { state.step = state.step?.withSaving(saving) }

    func discardLater(_ file: PreparedFile) {
        let uploads = uploads
        bag.run { await uploads.discard(file) }
    }

    func updateLate(_ edit: (inout LateForm) -> Void) {
        guard case .lateReason(var form) = state.step else { return }
        edit(&form)
        state.step = .lateReason(form)
    }

    func updateLateCheck(_ edit: (inout LateCheck) -> Void) {
        guard case .lateReview(var check) = state.step else { return }
        edit(&check)
        state.step = .lateReview(check)
    }

    func updateClosure(_ edit: (inout ClosureForm) -> Void) {
        guard case .closure(var form) = state.step else { return }
        edit(&form)
        state.step = .closure(form)
    }

    func updateRequirements(_ edit: (inout RequirementsForm) -> Void) {
        guard case .requirements(var form) = state.step else { return }
        edit(&form)
        state.step = .requirements(form)
    }

    func updateSendBack(_ edit: (inout SendBackForm) -> Void) {
        guard case .sendBack(var form) = state.step else { return }
        edit(&form)
        state.step = .sendBack(form)
    }

    /// The server's defaults, with what was typed before kept for fields that are still asked.
    static func values(
        _ requirements: [StageRequirement],
        keeping kept: [Int: [String: String]]
    ) -> [Int: [String: String]] {
        var values = RequirementChecks.initial(requirements)
        for requirement in requirements {
            for (key, value) in kept[requirement.actionId] ?? [:]
            where requirement.fields.contains(where: { $0.key == key }) && !value.isEmpty {
                values[requirement.actionId, default: [:]][key] = value
            }
        }
        return values
    }

    static func problem(_ error: any Error) -> UploadProblem { (error as? UploadRefused)?.problem ?? .failed }
}
