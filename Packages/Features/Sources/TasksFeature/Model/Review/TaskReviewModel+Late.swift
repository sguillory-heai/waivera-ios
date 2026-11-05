import Foundation
import WaiveraAPI
import WaiveraData

/// The late reason (sent by the assignee, reviewed or corrected by a reviewer) and sending a
/// task back.
extension TaskReviewModel {
    /// The picked file's attachment id, the one kept from before, or none.
    struct EvidenceRef: Equatable { var value: Int? }

    func openLateForm(_ context: LateContext, due: CalendarDate?) {
        let returned = context.justification.flatMap { $0.returned ? $0 : nil }
        let delay = returned == nil ? context.suggestedDelay : nil
        var form = LateForm()
        form.reasonId = returned?.reasonId ?? delay?.reasonId
        form.explanation = returned?.explanation ?? delay?.explanation ?? ""
        form.typed = !form.explanation.isEmpty
        form.delayId = delay?.id
        form.delayEvidenceId = delay?.evidenceId
        form.existingEvidenceId = returned?.evidenceId
        form.returned = returned != nil
        form.correction = context.correction
        form.due = due
        show(.lateReason(form))
        loadLateReasons()
    }

    func loadLateReasons() {
        updateLate { $0.reasons = .loading }
        let review = review
        bag.replace("lateReasons") { [weak self] in
            let result = await attempt { try await review.lateReasons() }
            guard let self, !Task.isCancelled else { return }
            self.updateLate { form in
                switch result {
                case .success(let reasons): form.reasons = .ready(reasons)
                case .failure: form.reasons = .failed
                }
            }
        }
    }

    /// web `applyPreset`: a reason's preset fills the explanation only until something is typed.
    func setLateReason(_ id: Int64) {
        updateLate { form in
            guard let reason = form.reasons.value?.first(where: { $0.id == id }) else { return }
            if !form.typed { form.explanation = reason.preset ?? "" }
            // Another reason than the delay's no longer reuses the delay.
            if id != form.reasonId { form.delayId = nil }
            form.reasonId = id
            form.failed = false
        }
    }

    func setLateExplanation(_ text: String) {
        updateLate { form in
            guard form.explanation != text else { return }
            form.explanation = text
            form.typed = true
            form.failed = false
        }
    }

    /// web "Use a different justification": forget the reported delay and start blank.
    func dropDelay() {
        updateLate { form in
            form.delayId = nil
            form.reasonId = nil
            form.explanation = ""
            form.typed = false
        }
    }

    func pickEvidence(_ files: [PickedFile]) {
        guard let file = files.first, case .lateReason(let form) = state.step, !form.isSaving else { return }
        if let old = form.evidence { discardLater(old) }
        updateLate { form in
            form.evidence = nil
            form.uploadedEvidenceId = nil
            form.evidenceChecking = true
            form.evidenceProblem = nil
            form.failed = false
        }
        preparing?.cancel()
        let uploads = uploads
        preparing = Task { [weak self] in
            let result = await attempt { try await uploads.prepare(file, purpose: .evidence) }
            guard let self, !Task.isCancelled else { return }
            self.updateLate { form in
                form.evidenceChecking = false
                switch result {
                case .success(let prepared): form.evidence = prepared
                case .failure(let error): form.evidenceProblem = Self.problem(error)
                }
            }
        }
    }

    func removeEvidence() {
        guard case .lateReason(let form) = state.step, !form.isSaving else { return }
        if let file = form.evidence { discardLater(file) }
        updateLate { form in
            form.evidence = nil
            form.uploadedEvidenceId = nil
            form.evidenceProblem = nil
        }
    }

    func submitLate() {
        guard case .lateReason(let form) = state.step, !form.isSaving else { return }
        guard form.isValid, let reasonId = form.reasonId else { return updateLate { $0.showErrors = true } }
        updateLate { form in
            form.isSaving = true
            form.failed = false
            form.evidenceProblem = nil
        }
        let review = review
        let id = taskId
        bag.run { [weak self] in
            guard let self, let evidence = await self.uploadEvidence(form) else { return }
            let explanation = form.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = await attempt {
                if let editing = form.editingId {
                    let edit = LateEdit(reasonId: reasonId, explanation: explanation, evidenceId: evidence.value)
                    try await review.agreeLate(taskId: id, justificationId: editing, note: nil, edit: edit)
                } else {
                    try await review.justify(
                        taskId: id,
                        reasonId: reasonId,
                        explanation: explanation,
                        evidenceId: evidence.value,
                        delayId: form.delayId
                    )
                }
            }
            switch result {
            case .success: self.lateSaved()
            case .failure:
                self.updateLate { form in
                    form.isSaving = false
                    form.failed = true
                }
            }
        }
    }

    /// Uploads a newly picked file once: a retry after a failed send reuses its id. Nil stops the send.
    private func uploadEvidence(_ form: LateForm) async -> EvidenceRef? {
        guard let file = form.evidence else { return EvidenceRef(value: form.keptEvidenceId) }
        let uploads = uploads
        let id = taskId
        let result = await attempt { try await uploads.sendEvidence(taskId: id, file: file) }
        switch result {
        case .success(let attachmentId):
            updateLate { form in
                form.evidence = nil
                form.uploadedEvidenceId = attachmentId
            }
            return EvidenceRef(value: attachmentId)
        case .failure(let error):
            updateLate { form in
                form.isSaving = false
                form.evidenceProblem = Self.problem(error)
            }
            return nil
        }
    }

    /// The late reason is saved, so its sheet closes: a later step that fails then reports its own
    /// failure instead of offering to send the reason again.
    private func lateSaved() {
        state.step = nil
        onEffect?(.reload)
        advance()
    }

    func agreeLate() {
        guard case .lateReview(let check) = state.step, let justification = check.context.justification,
            !check.isSaving, !check.noteTooLong
        else { return }
        updateLateCheck { check in
            check.isSaving = true
            check.failed = false
        }
        let review = review
        let id = taskId
        let note = check.note
        bag.run { [weak self] in
            let result = await attempt {
                try await review.agreeLate(taskId: id, justificationId: justification.id, note: note, edit: nil)
            }
            guard let self else { return }
            switch result {
            case .success: self.lateSaved()
            case .failure:
                self.updateLateCheck { check in
                    check.isSaving = false
                    check.failed = true
                }
            }
        }
    }

    func setLateNote(_ text: String) {
        updateLateCheck { check in
            guard check.note != text else { return }
            check.note = text
            check.failed = false
        }
    }

    /// The reviewer corrects the reason themself, then agrees with the corrected one.
    func editLate() {
        guard case .lateReview(let check) = state.step, !check.isSaving,
            let justification = check.context.justification
        else { return }
        var form = LateForm()
        form.reasonId = justification.reasonId
        form.explanation = justification.explanation
        form.typed = !justification.explanation.isEmpty
        form.existingEvidenceId = justification.evidenceId
        form.editingId = justification.id
        form.due = chain?.task.due
        show(.lateReason(form))
        loadLateReasons()
    }

    /// Return the late reason for correction: the task goes back to a chosen earlier step.
    func returnLate() {
        guard case .lateReview(let check) = state.step, !check.isSaving,
            let justification = check.context.justification
        else { return }
        openSendBack(lateReasonId: justification.id)
    }

    // MARK: Send back

    func startReject() {
        guard !state.busy else { return }
        state.rejecting = true
        openSendBack(lateReasonId: nil)
    }

    private func openSendBack(lateReasonId: Int64?) {
        show(.sendBack(SendBackForm(lateReasonId: lateReasonId)))
        loadSendBackOptions()
    }

    func loadSendBackOptions() {
        updateSendBack { $0.options = .loading }
        let review = review
        let id = taskId
        bag.replace("sendBackOptions") { [weak self] in
            let result = await attempt { try await review.sendBackOptions(taskId: id) }
            guard let self, !Task.isCancelled else { return }
            self.updateSendBack { form in
                switch result {
                case .success(let options):
                    form.options = .ready(options)
                    // One choice is picked for the person, as the web does.
                    if form.approvalId == nil, options.count == 1 { form.approvalId = options[0].approvalId }
                case .failure:
                    form.options = .failed
                }
            }
        }
    }

    func chooseSendBack(_ approvalId: Int) {
        updateSendBack { form in
            form.approvalId = approvalId
            form.failed = false
        }
    }

    func setFeedback(_ text: String) {
        updateSendBack { form in
            guard form.feedback != text else { return }
            form.feedback = text
            form.failed = false
        }
    }

    func setMinutes(_ text: String) {
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(SendBackForm.minuteDigits))
        updateSendBack { form in
            guard form.minutes != digits else { return }
            form.minutes = digits
            form.failed = false
        }
    }

    func submitSendBack() {
        guard case .sendBack(let form) = state.step, !form.isSaving else { return }
        guard form.isValid, let option = form.option, let minutes = form.minutesValue else {
            return updateSendBack { $0.showErrors = true }
        }
        updateSendBack { form in
            form.isSaving = true
            form.failed = false
        }
        let review = review
        let id = taskId
        let feedback = form.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        let lateReasonId = form.lateReasonId
        bag.run { [weak self] in
            let result = await attempt {
                try await review.sendBack(
                    taskId: id,
                    option: option,
                    feedback: feedback,
                    minutes: minutes,
                    lateReasonId: lateReasonId
                )
            }
            guard let self else { return }
            switch result {
            case .success: self.stop(.sentBack, reload: true)
            case .failure:
                self.updateSendBack { form in
                    form.isSaving = false
                    form.failed = true
                }
            }
        }
    }
}
