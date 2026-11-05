import Foundation
import WaiveraAPI
import WaiveraData

/// The sheets' answers: the confirmations, the employee closure and the stage's requirements.
extension TaskReviewModel {
    func confirmAll() { moveOn { $0.confirmedAll = true } }

    func discardDrafts() { moveOn { $0.discardDrafts = true } }

    func chooseDrive(original: Bool) {
        guard case .driveSection(let previous, _) = state.step else { return }
        show(.driveSection(previous: previous, useOriginal: original))
    }

    func confirmDrive() {
        guard case .driveSection(_, let original) = state.step else { return }
        moveOn { $0.useOriginal = original }
    }

    func completeAnyway() {
        guard case .related(let blocked, let tasks, let saving) = state.step, !blocked, !saving,
            var current = chain
        else { return }
        current.acknowledged = true
        chain = current
        show(.related(blocked: false, tasks: tasks, isSaving: true))
        advance()
    }

    func openRelated(_ taskId: Int) {
        guard !state.stepSaving else { return }
        dismiss()
        onEffect?(.openTask(taskId: taskId))
    }

    // MARK: Employee closure

    func setMerge(_ merge: Bool) {
        updateClosure {
            $0.merge = merge
            $0.failed = false
        }
    }

    func togglePdf(_ id: String) {
        updateClosure { form in
            if form.picked.contains(id) { form.picked.remove(id) } else { form.picked.insert(id) }
            form.failed = false
        }
    }

    func movePdf(_ id: String, up: Bool) {
        updateClosure { form in
            guard let index = form.order.firstIndex(of: id) else { return }
            let target = up ? index - 1 : index + 1
            guard form.order.indices.contains(target) else { return }
            form.order.swapAt(index, target)
        }
    }

    func setExpiration(_ date: CalendarDate) {
        updateClosure {
            $0.expiration = date
            $0.failed = false
        }
    }

    func saveClosure() {
        guard case .closure(let form) = state.step, !form.isSaving else { return }
        guard form.isValid else { return updateClosure { $0.showErrors = true } }
        updateClosure {
            $0.isSaving = true
            $0.failed = false
        }
        let merge = form.merge ? form.order.filter { form.picked.contains($0) } : nil
        let expiration = form.options.needsExpiration ? form.expiration : nil
        let review = review
        let id = taskId
        bag.run { [weak self] in
            let result = await attempt {
                try await review.chooseClosure(taskId: id, merge: merge, nextExpiration: expiration)
            }
            guard let self else { return }
            switch result {
            case .success: self.moveOn { $0.closurePrepared = true }
            case .failure:
                self.updateClosure {
                    $0.isSaving = false
                    $0.failed = true
                }
            }
        }
    }

    // MARK: Stage requirements

    func setRequirement(actionId: Int, key: String, value: String) {
        updateRequirements { form in
            form.values[actionId, default: [:]][key] = value
            form.confirmWarnings = false
            form.failed = false
        }
    }

    func submitRequirements() {
        guard case .requirements(let form) = state.step, !form.isSaving, form.supported else { return }
        let plan = chain?.task.planDates
        let today = today
        var errors: [Int: [String: RequirementIssue]] = [:]
        var warnings: [Int: [String: RequirementIssue]] = [:]
        for requirement in form.requirements {
            let result = RequirementChecks.check(
                requirement,
                values: form.values[requirement.actionId] ?? [:],
                plan: plan,
                today: today
            )
            if !result.errors.isEmpty { errors[requirement.actionId] = result.errors }
            if !result.warnings.isEmpty { warnings[requirement.actionId] = result.warnings }
        }
        if !errors.isEmpty {
            updateRequirements {
                $0.errors = errors
                $0.warnings = warnings
            }
        } else if !warnings.isEmpty, !form.confirmWarnings {
            updateRequirements {
                $0.errors = [:]
                $0.warnings = warnings
                $0.confirmWarnings = true
            }
        } else {
            updateRequirements {
                $0.errors = [:]
                $0.isSaving = true
                $0.failed = false
            }
            guard var current = chain else { return }
            current.answers = form.values
            chain = current
            advance()
        }
    }
}
