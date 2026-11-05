import Foundation
import Observation
import WaiveraAPI
import WaiveraData

struct ActivityRow: Identifiable, Hashable, Sendable {
    var id: Int
    var type: String
    var moment: TaskMoment?
    var byMe: Bool
    var author: String?
    var description: String?
    var minutes: Int
    /// Just logged here, so it lands with the arrival motion.
    var isNew = false
}

/// The active delay, already worded: `through` is "Nov 20", nil when the server sent no end.
struct DelayNote: Hashable, Sendable {
    var through: String?
    var reason: String?
    var explanation: String?
}

/// The banner for a pending request, already worded for the person's day.
struct PendingBanner: Hashable, Sendable {
    var kind: RequestKind
    var newDue: String?
    var delayStart: String?
    var delayEnd: String?

    var title: String {
        switch kind {
        case .moreTime: TasksStrings.text("tasks.pending.moreTime.title")
        case .delay: TasksStrings.text("tasks.pending.delay.title")
        case .closure: TasksStrings.text("tasks.pending.closure.title")
        default: TasksStrings.text("tasks.pending.other.title")
        }
    }

    var message: String {
        switch kind {
        case .moreTime:
            newDue.map { TasksStrings.format("tasks.pending.moreTime", $0) }
                ?? TasksStrings.text("tasks.pending.moreTime.short")
        case .delay:
            if let delayStart, let delayEnd {
                TasksStrings.format("tasks.pending.delay", delayStart, delayEnd)
            } else {
                TasksStrings.text("tasks.pending.delay.short")
            }
        case .closure: TasksStrings.text("tasks.pending.closure")
        default: TasksStrings.text("tasks.pending.other")
        }
    }
}

struct TaskDetailScreenState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case loading, error, content }

    var phase: Phase = .loading
    var task: TaskDetail?
    var due: DueText = .none
    var dueDate: String?
    var startDate: String?
    var activity: Loadable<[ActivityRow]> = .loading
    /// Newest first; an empty list hides the section.
    var files: Loadable<[FileRow]> = .loading
    var log: LogForm?
    var error: WaiveraError?
    /// A change request waiting on review, from the server or just sent from here.
    var pending: PendingBanner?
    /// What the person may ask for now; empty hides Ask for a change.
    var askChoices: [AskKind] = []
    var ask: AskForm?
    /// Today in the saved zone.
    var today: CalendarDate?
    var zone: TimeZone = .current
    /// The approved delay covering today: the task is not really overdue while it lasts.
    var delay: DelayNote?

    /// The approval stage the task waits on, for Details.
    var step: StepNote? { task.flatMap { StepNote.of($0.steps) } }

    /// Past due with no delay covering it; the due date and status turn red only then.
    var late: Bool { due.overdue && delay == nil }
    var canLog: Bool { task.map { !$0.isFinished } ?? false }
    /// sprout_web `isReadOnly`: completed, closed and deleted tasks take no files.
    var canUpload: Bool {
        guard canLog, let task else { return false }
        if case .other(let name) = task.state, name.caseInsensitiveCompare("Deleted") == .orderedSame { return false }
        return true
    }
    var canAsk: Bool { canLog && pending == nil && !askChoices.isEmpty }
}

/// One task (Android `TaskDetailViewModel`): its facts, activity, Log activity and Ask for a
/// change. The task shows while its activity is still loading.
@MainActor
@Observable
final class TaskDetailModel {
    private(set) var state = TaskDetailScreenState()
    let feedback = TasksFeedback()
    /// Required files and uploads, followed while the screen shows.
    let uploads: TaskUploadsModel
    /// Submit, Approve and Reject with every step the web runs.
    let review: TaskReviewModel
    /// View, save or share a tapped file.
    let fileActions: TaskFileActionsModel
    /// Opens a related task a review step points at.
    @ObservationIgnored var onOpen: ((ReviewEffect) -> Void)?

    @ObservationIgnored let taskId: Int
    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private let bag = TaskBag()
    @ObservationIgnored private var local = Local()
    @ObservationIgnored private var access = RequestAccess()
    @ObservationIgnored private var started = false

    private struct PendingDraft: Equatable {
        var kind: AskKind
        var newDue: CalendarDate?
        var delay: DelayPeriod?
    }

    private struct Local {
        var phase: TaskDetailScreenState.Phase = .loading
        var task: TaskDetail?
        var activity: Loadable<[TaskActivity]> = .loading
        var files: Loadable<[TaskAttachment]> = .loading
        var newIds: Set<Int> = []
        var log: LogForm?
        var error: WaiveraError?
        var options: ChangeOptions?
        var ask: AskForm?
        /// Drawn as pending while the request is on its way, until the server's own copy shows.
        var optimistic: PendingDraft?
    }

    init(taskId: Int, environment: DataEnvironment) {
        self.taskId = taskId
        self.environment = environment
        uploads = TaskUploadsModel(taskId: taskId, environment: environment)
        review = TaskReviewModel(taskId: taskId, environment: environment)
        fileActions = TaskFileActionsModel(taskId: taskId, environment: environment, feedback: feedback)
        rebuild()
        uploads.onFilesChanged = { [weak self] in self?.loadFiles() }
        review.onEffect = { [weak self] effect in self?.reviewEffect(effect) }
    }

    /// The chain's results: a reload, a file or task to open, or a message.
    private func reviewEffect(_ effect: ReviewEffect) {
        switch effect {
        case .reload: load()
        case .openTask: onOpen?(effect)
        default: if let message = effect.message { feedback.show(message) }
        }
    }

    /// Starts Submit or Approve on the task as it shows now.
    func startReview(_ action: ReviewAction) {
        guard let task = local.task else { return }
        if task.review.canApproveAll {
            review.askScope(action, task: task)
        } else {
            review.start(action, task: task)
        }
    }

    func run() async {
        if !started {
            started = true
            load()
        }
        let uploads = uploads
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await uploads.run() }
            group.addTask { await self.followAccess() }
        }
    }

    private func followAccess() async {
        for await value in environment.requests.access() {
            access = value
            rebuild()
        }
    }

    /// Loads the task, its activity, files and options. Each part replaces the same part still in
    /// flight, so a pull to refresh or a retry never lets an older answer land last.
    func load() {
        _ = startLoading()
    }

    /// Pull to refresh: everything again, finishing with the activity it shows.
    func refresh() async {
        await startLoading().value
    }

    func loadActivity() {
        _ = reloadActivity()
    }

    private func startLoading() -> Task<Void, Never> {
        if local.task == nil { local.phase = .loading }
        rebuild()
        let tasks = environment.tasks
        let id = taskId
        bag.replace("task") { [weak self] in
            let result = await attempt { try await tasks.task(id: id) }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let task):
                self.local.phase = .content
                self.local.task = task
                self.local.error = nil
                // A request the server now shows replaces the one drawn here while it was sent.
                if task.pendingRequest != nil { self.local.optimistic = nil }
            case .failure(let error):
                if self.local.task == nil {
                    self.local.phase = .error
                    self.local.error = WaiveraError.from(error)
                }
            }
            self.rebuild()
        }
        loadFiles()
        loadOptions()
        return reloadActivity()
    }

    /// `newSince` marks rows that were not in that set as just added (after Log activity).
    @discardableResult
    private func reloadActivity(newSince before: Set<Int>? = nil) -> Task<Void, Never> {
        let tasks = environment.tasks
        let id = taskId
        return bag.replace("activity") { [weak self] in
            let result = await attempt { try await tasks.activity(taskId: id) }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let items):
                self.local.activity = .ready(items)
                if let before { self.local.newIds = Set(items.map(\.id)).subtracting(before) }
            case .failure:
                if self.local.activity.value == nil { self.local.activity = .failed }
            }
            self.rebuild()
        }
    }

    func loadFiles() {
        if local.files.value == nil {
            local.files = .loading
            rebuild()
        }
        let tasks = environment.tasks
        let id = taskId
        bag.replace("files") { [weak self] in
            let result = await attempt { try await tasks.attachments(taskId: id) }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let files): self.local.files = .ready(files)
            case .failure: if self.local.files.value == nil { self.local.files = .failed }
            }
            self.rebuild()
        }
    }

    /// What a tap on a file does: the phone's viewer, or the task on the web for a file it
    /// cannot show (another type, or over the size limit).
    enum FileOpening: Equatable {
        case viewer(attachmentId: Int)
        case web(URL)
    }

    /// A tap on a file: the sheet to view, save or share it when the person may download it;
    /// otherwise straight to the viewer or the web.
    func choose(file row: FileRow) -> FileOpening? {
        let attachment = local.files.value?.first { $0.attachmentId == row.id }
        if fileActions.choose(row, attachment: attachment, access: access) { return nil }
        return open(file: row)
    }

    func open(file row: FileRow) -> FileOpening? {
        if row.viewable { return .viewer(attachmentId: row.id) }
        return webURL().map(FileOpening.web)
    }

    /// The web app's page for the task, or nil (with a note) when no web app is configured.
    func webURL() -> URL? {
        guard let path = local.task?.webPath else { return nil }
        guard let url = TasksWeb.url(path, base: environment.webBaseURL) else {
            feedback.show(TasksStrings.text("tasks.web.unavailable"))
            return nil
        }
        return url
    }

    // MARK: Log activity

    func startLog() {
        guard state.canLog else { return }
        let now = Date(timeIntervalSince1970: (environment.clock.now.timeIntervalSince1970 / 60).rounded(.down) * 60)
        local.log = LogForm(completedAt: now)
        rebuild()
        loadTypes()
    }

    func loadTypes() {
        updateLog { $0.types = .loading }
        let tasks = environment.tasks
        bag.run { [weak self] in
            let result = await attempt { try await tasks.activityTypes() }
            self?.updateLog { form in
                switch result {
                case .success(let types): form.types = .ready(types)
                case .failure: form.types = .failed
                }
            }
        }
    }

    func dismissLog() {
        guard let form = local.log, !form.isSaving else { return }
        local.log = nil
        rebuild()
        discard(form.file)
    }

    func chooseType(_ id: Int) {
        guard let form = local.log, let type = form.types.value?.first(where: { $0.id == id }) else { return }
        // A file picked for one type goes when the new type takes none; once sent it stays sent.
        let dropFile = !type.needsFile && form.sentAs == nil
        updateLog { form in
            let wasMinutesLocked = form.minutesLocked
            let wasDescriptionLocked = form.descriptionLocked
            form.typeId = id
            form.minutes = type.recommendedMinutes ?? (wasMinutesLocked ? LogForm.defaultMinutes : form.minutes)
            form.description = type.fixedDescription ?? (wasDescriptionLocked ? "" : form.description)
            form.failed = false
            if dropFile {
                form.file = nil
                form.fileProblem = nil
            }
        }
        if dropFile { discard(form.file) }
    }

    /// The picker's result for the activity's file.
    func pickLogFile(_ picked: PickedFile) {
        guard let form = local.log, !form.isSaving, form.sentAs == nil else { return }
        let previous = form.file
        updateLog {
            $0.fileChecking = true
            $0.fileProblem = nil
            $0.file = nil
            $0.failed = false
        }
        discard(previous)
        let repository = environment.uploads
        bag.replace("logFile") { [weak self] in
            let result = await attempt { try await repository.prepare(picked) }
            guard let self, !Task.isCancelled else { return }
            guard self.local.log != nil else {
                if case .success(let file) = result { await repository.discard(file) }
                return
            }
            self.updateLog { form in
                form.fileChecking = false
                switch result {
                case .success(let file): form.file = file
                case .failure(let error): form.fileProblem = (error as? UploadRefused)?.problem ?? .unreadable
                }
            }
        }
    }

    func removeLogFile() {
        guard let form = local.log, !form.isSaving, form.sentAs == nil else { return }
        updateLog {
            $0.file = nil
            $0.fileProblem = nil
        }
        discard(form.file)
    }

    private func discard(_ file: PreparedFile?) {
        guard let file else { return }
        let repository = environment.uploads
        bag.run { await repository.discard(file) }
    }

    func stepMinutes(up: Bool) {
        updateLog { form in
            guard !form.minutesLocked else { return }
            let next = form.minutes + (up ? LogForm.stepMinutes : -LogForm.stepMinutes)
            form.minutes = min(max(next, LogForm.stepMinutes), LogForm.maxMinutes)
        }
    }

    func setDescription(_ text: String) {
        updateLog { form in
            guard !form.descriptionLocked else { return }
            form.description = String(text.prefix(LogForm.maxDescription))
            form.failed = false
        }
    }

    /// `date` and `minuteOfDay` are wall-clock values in the employee's saved zone.
    func setWhen(date: CalendarDate, minuteOfDay: Int) {
        let zone = environment.calendar.scheduleTimeZone().zone
        updateLog { form in
            form.completedAt = date.instant(atMinute: minuteOfDay, in: zone)
        }
    }

    func submitLog() {
        guard let form = state.log, !form.isSaving else { return }
        guard form.isValid, let typeId = form.typeId else {
            updateLog { $0.showErrors = true }
            return
        }
        let file = form.needsFile && form.sentAs == nil ? form.file : nil
        updateLog {
            $0.isSaving = true
            $0.isUploading = file != nil
            $0.failed = false
            $0.fileProblem = nil
        }
        let tasks = environment.tasks
        let activity = NewActivity(
            taskId: taskId,
            typeId: typeId,
            minutes: form.needsFile ? (form.type?.recommendedMinutes ?? 0) : form.minutes,
            completedAt: form.completedAt,
            description: form.description
        )
        bag.run { [weak self] in
            // As on the web, the file goes up first and the activity is logged only once it is there.
            var sentAs = form.sentAs
            if let file {
                guard let saved = await self?.uploadLogFile(form, file: file) else { return }
                sentAs = saved
                self?.updateLog {
                    $0.isUploading = false
                    $0.sentAs = saved
                }
            }
            do {
                try await tasks.logActivity(activity)
                guard let self else { return }
                let before = Set(self.local.activity.value?.map(\.id) ?? [])
                self.local.log = nil
                let numbered = sentAs.flatMap { $0.isEmpty || $0 == form.fileSavedName ? nil : $0 }
                self.feedback.show(
                    numbered.map { TasksStrings.format("tasks.log.doneSavedAs", $0) }
                        ?? TasksStrings.text("tasks.log.done")
                )
                self.rebuild()
                self.reloadActivity(newSince: before)
                if sentAs != nil { self.loadFiles() }
            } catch {
                self?.updateLog {
                    $0.isSaving = false
                    $0.failed = true
                }
            }
        }
    }

    /// The saved name, or nil when the upload failed and the form now says why.
    private func uploadLogFile(_ form: LogForm, file: PreparedFile) async -> String? {
        do {
            let saved = try await environment.uploads.sendNow(
                taskId: taskId,
                file: file,
                template: form.type?.fileTemplate
            )
            return saved ?? form.fileSavedName ?? ""
        } catch {
            let problem = (error as? UploadRefused)?.problem ?? .failed
            // A file the server won't take is dropped so another can be picked; a failed send
            // keeps it for Log activity to try again.
            let keep = problem.canRetry
            updateLog {
                $0.isSaving = false
                $0.isUploading = false
                $0.fileProblem = problem
                if !keep { $0.file = nil }
            }
            if !keep { discard(file) }
            return nil
        }
    }

    // MARK: Ask for a change

    func startAsk() {
        guard state.canAsk else { return }
        let choices = state.askChoices
        local.ask = AskForm(choices: choices)
        rebuild()
        // One choice goes straight to its form.
        if choices.count == 1, let only = choices.first { chooseAsk(only) }
    }

    func chooseAsk(_ kind: AskKind) {
        let options = local.options
        let due = local.task?.due
        updateAsk { form in
            form = AskForm(
                choices: form.choices,
                kind: kind,
                explanation: form.explanation,
                currentDue: options?.currentDue ?? due,
                delay: options?.delay
            )
        }
        loadAskReasons()
        if kind != .closure { loadAskFiles() }
    }

    /// From a form back to the chooser, when there was a choice to make.
    @discardableResult
    func backToChoices() -> Bool {
        guard let form = local.ask, !form.isSaving, form.kind != nil, form.choices.count > 1 else { return false }
        updateAsk { $0 = AskForm(choices: $0.choices) }
        return true
    }

    func dismissAsk() {
        guard local.ask?.isSaving != true else { return }
        local.ask = nil
        rebuild()
    }

    func loadAskReasons() {
        guard let kind = local.ask?.kind else { return }
        updateAsk { $0.reasons = .loading }
        let requests = environment.requests
        bag.run { [weak self] in
            let result = await attempt { () async throws -> [ChangeReason] in
                switch kind {
                case .moreTime: try await requests.moreTimeReasons()
                case .delay: try await requests.delayReasons()
                case .closure: try await requests.closureReasons()
                }
            }
            self?.updateAsk { form in
                guard form.kind == kind else { return }
                switch result {
                case .success(let reasons): form.reasons = .ready(reasons)
                case .failure: form.reasons = .failed
                }
            }
        }
    }

    func loadAskFiles() {
        updateAsk { $0.files = .loading }
        let requests = environment.requests
        let id = taskId
        bag.run { [weak self] in
            let result = await attempt { try await requests.files(taskId: id) }
            self?.updateAsk { form in
                switch result {
                case .success(let files): form.files = .ready(files)
                case .failure: form.files = .failed
                }
            }
        }
    }

    func setAskReason(_ id: Int64) {
        updateAsk { form in
            guard let reason = form.reasons.value?.first(where: { $0.id == id }) else { return }
            form.reasonId = reason.id
            if !reason.requiresEvidence { form.evidenceId = nil }
            form.failed = false
        }
    }

    func setAskDue(_ date: CalendarDate) {
        updateAsk {
            $0.newDue = date
            $0.failed = false
        }
    }

    func setAskExplanation(_ text: String) {
        updateAsk {
            $0.explanation = String(text.prefix(AskForm.maxExplanation + AskForm.explanationSlack))
            $0.failed = false
        }
    }

    func setAskEvidence(_ id: Int?) {
        updateAsk {
            $0.evidenceId = id
            $0.failed = false
        }
    }

    /// Sends the request. The pending banner shows at once and the sheet closes; if the server
    /// says no, the banner goes and the sheet comes back with everything still filled in.
    func submitAsk() {
        guard let form = local.ask, let kind = form.kind, !form.isSaving else { return }
        guard form.isValid, let reasonId = form.reasonId else {
            updateAsk { $0.showErrors = true }
            return
        }
        local.ask = nil
        local.optimistic = PendingDraft(kind: kind, newDue: form.newDue, delay: form.delay)
        rebuild()
        bag.run { [weak self] in
            guard let self else { return }
            let result = await self.send(kind, form: form, reasonId: reasonId)
            switch result {
            case .sent(let outcome):
                if outcome == .approved { self.local.optimistic = nil }
                self.local.options = nil
                let key: String =
                    switch (kind, outcome) {
                    case (.moreTime, .approved): "tasks.asked.inEffect.moreTime"
                    case (.delay, .approved): "tasks.asked.inEffect.delay"
                    case (.moreTime, _): "tasks.asked.moreTime"
                    case (.delay, _): "tasks.asked.delay"
                    case (.closure, _): "tasks.asked.closure"
                    }
                self.feedback.show(TasksStrings.text(key))
                self.load()
            case .delayChanged(let period):
                self.local.optimistic = nil
                var back = form
                back.delayChanged = true
                back.delay = period
                self.local.ask = back
                self.rebuild()
            case .failed:
                self.local.optimistic = nil
                var back = form
                back.failed = true
                self.local.ask = back
                self.rebuild()
            }
        }
    }

    // MARK: Private

    private enum SendResult {
        case sent(RequestOutcome)
        case delayChanged(DelayPeriod?)
        case failed
    }

    private func send(_ kind: AskKind, form: AskForm, reasonId: Int64) async -> SendResult {
        let requests = environment.requests
        let evidence = form.needsEvidence ? form.evidenceId : nil
        do {
            switch kind {
            case .moreTime:
                guard let due = form.newDue else { return .failed }
                return .sent(
                    try await requests.askMoreTime(
                        taskId: taskId,
                        newDue: due,
                        reasonId: reasonId,
                        explanation: form.explanation,
                        evidenceId: evidence
                    )
                )
            case .delay:
                // The period is the server's; check it again just before sending, as the web does.
                let fresh = try await requests.options(taskId: taskId)
                local.options = fresh
                guard let period = fresh.delay, period == form.delay else { return .delayChanged(fresh.delay) }
                return .sent(
                    try await requests.reportDelay(
                        taskId: taskId,
                        period: period,
                        reasonId: reasonId,
                        explanation: form.explanation,
                        evidenceId: evidence
                    )
                )
            case .closure:
                try await requests.askClosure(taskId: taskId, reasonId: reasonId, comment: form.explanation)
                return .sent(.pending)
            }
        } catch {
            return .failed
        }
    }

    /// What may be asked for here, from the same role policies and eligibility check the web uses.
    private func loadOptions() {
        let requests = environment.requests
        let id = taskId
        bag.replace("options") { [weak self] in
            await requests.ensureAccess()
            guard let options = try? await requests.options(taskId: id), !Task.isCancelled else { return }
            self?.local.options = options
            self?.rebuild()
        }
    }

    private func updateLog(_ transform: (inout LogForm) -> Void) {
        guard var form = local.log else { return }
        transform(&form)
        local.log = form
        rebuild()
    }

    private func updateAsk(_ transform: (inout AskForm) -> Void) {
        guard var form = local.ask else { return }
        transform(&form)
        local.ask = form
        rebuild()
    }

    private func choices() -> [AskKind] {
        // Nothing is offered until the server's check has answered, so a request already waiting
        // is never doubled while it loads or after it failed.
        guard let task = local.task, let options = local.options, !options.hasPendingRequest else { return [] }
        var choices: [AskKind] = []
        if task.isClientTask, access.canAskMoreTime, options.canAskMoreTime { choices.append(.moreTime) }
        if task.isClientTask, access.canAskMoreTime, options.delay != nil { choices.append(.delay) }
        if access.canAskClosure { choices.append(.closure) }
        return choices
    }

    private func pendingBanner(today: CalendarDate) -> PendingBanner? {
        func day(_ date: CalendarDate?) -> String? { date.map { TaskFormat.date($0, today: today) } }
        if let draft = local.optimistic {
            return PendingBanner(
                kind: draft.kind.requestKind,
                newDue: day(draft.newDue),
                delayStart: day(draft.delay?.start),
                delayEnd: day(draft.delay?.end)
            )
        }
        guard let request = local.task?.pendingRequest else { return nil }
        return PendingBanner(
            kind: request.kind,
            newDue: day(request.requestedDue),
            delayStart: day(request.delayStart),
            delayEnd: day(request.delayEnd)
        )
    }

    private func rebuild() {
        let zone = environment.calendar.scheduleTimeZone().zone
        let now = environment.clock.now
        let today = CalendarDate(now, in: zone)
        let me = environment.session.currentState.user?.id
        var next = TaskDetailScreenState()
        next.phase = local.phase
        next.task = local.task
        next.due = TaskFormat.due(local.task?.due, today: today)
        next.dueDate = local.task?.due.map { TaskFormat.date($0, today: today) }
        next.startDate = local.task?.start.map { TaskFormat.date($0, today: today) }
        next.activity = local.activity.map { items in
            items.map { item in
                ActivityRow(
                    id: item.id,
                    type: item.type,
                    moment: item.at.map { TaskFormat.moment($0, zone: zone, today: today) },
                    byMe: me != nil && item.authorId == me,
                    author: item.authorName,
                    description: item.description,
                    minutes: item.minutes,
                    isNew: local.newIds.contains(item.id)
                )
            }
        }
        next.files = local.files.map { files in files.map { FileRow.make($0, zone: zone, today: today) } }
        next.log = local.log.map { form in
            var form = form
            form.inFuture = form.completedAt > now
            form.whenText = TaskFormat.moment(form.completedAt, zone: zone, today: today).text
            return form
        }
        next.error = local.error
        next.pending = pendingBanner(today: today)
        next.delay = local.task?.delay.map {
            DelayNote(
                through: $0.through.map { TaskFormat.shortDate($0, today: today) },
                reason: $0.reason,
                explanation: $0.explanation
            )
        }
        next.askChoices = choices()
        next.ask = local.ask
        next.today = today
        next.zone = zone
        if next != state { state = next }
    }
}
