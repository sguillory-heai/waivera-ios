import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// One file on its way up, as its row reads.
struct UploadRow: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var kind: FileKind
    var sizeBytes: Int64
    var state: UploadState
    var problem: UploadProblem?

    init(_ upload: TaskUpload) {
        id = upload.id
        name = upload.fileName
        kind = upload.kind
        sizeBytes = upload.sizeBytes
        state = upload.state
        problem = upload.problem
    }
}

/// A required file still missing; `upload` is the file going up for it, if any.
struct RequiredRow: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var isForm: Bool
    var removalPending: Bool
    var upload: UploadRow?
}

/// The Add a file sheet. An extra file on an employee task is filed under a category first, as
/// the web's upload modal asks; a required file takes one file, extra files up to ten.
struct UploadSheet: Equatable, Sendable {
    var target: UploadTarget
    var title: String?
    var needsCategory: Bool
    var categories: Loadable<[DocumentCategory]> = .loading
    var single: Bool

    var ready: Bool { !needsCategory || target.categoryId != nil }
}

struct TaskUploadsState: Equatable, Sendable {
    var required: Loadable<[RequiredRow]> = .loading
    /// Extra files going up, and any whose requirement is no longer listed.
    var uploads: [UploadRow] = []
    var sheet: UploadSheet?
}

/// Required files and uploads for one task (Android `TaskUploadsViewModel`, sprout_web
/// `TaskAttachmentSection`). Uploads go to the uploads repository, which sends them on its own;
/// a finished one shows as uploaded for a moment, then the task's lists load again and it
/// leaves, as the web's checkmark does.
@MainActor
@Observable
final class TaskUploadsModel {
    /// sprout_web shows the checkmark, then reloads the list after 2.5 s.
    static let settleDelay: Duration = .milliseconds(2_500)

    private(set) var state = TaskUploadsState()
    /// A file landed on the server: the task's file list should load again.
    @ObservationIgnored var onFilesChanged: () -> Void = {}

    @ObservationIgnored private let taskId: Int
    @ObservationIgnored private let repository: any TaskUploadsRepository
    @ObservationIgnored private let clock: any WaiveraClock
    @ObservationIgnored private let bag = TaskBag()
    @ObservationIgnored private var required: Loadable<[RequiredFile]> = .loading
    @ObservationIgnored private var uploads: [TaskUpload] = []
    @ObservationIgnored private var settling: Set<String> = []
    @ObservationIgnored private var failuresSeen: Set<String> = []
    @ObservationIgnored private var started = false

    init(taskId: Int, environment: DataEnvironment) {
        self.taskId = taskId
        repository = environment.uploads
        clock = environment.clock
    }

    /// Follows the task's uploads for as long as the screen shows.
    func run() async {
        if !started {
            started = true
            loadRequired()
        }
        for await list in repository.uploads(taskId: taskId) {
            uploads = list
            settle(list)
            rebuild()
        }
    }

    func loadRequired() {
        let repository = repository
        let id = taskId
        bag.replace("required") { [weak self] in
            let result = await attempt { try await repository.requiredFiles(taskId: id) }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let files): self.required = .ready(files)
            case .failure: if self.required.value == nil { self.required = .failed }
            }
            self.rebuild()
        }
    }

    func startRequired(_ id: Int) {
        guard let file = required.value?.first(where: { $0.id == id }), !file.isForm else { return }
        state.sheet = UploadSheet(
            target: UploadTarget(requirementId: file.id, requirementName: file.name, typeId: file.typeId),
            title: file.name,
            needsCategory: false,
            categories: .ready([]),
            single: true
        )
    }

    /// An extra file on an employee task is filed under a category first.
    func startExtra(employeeTask: Bool) {
        state.sheet = UploadSheet(target: UploadTarget(), title: nil, needsCategory: employeeTask, single: false)
        if employeeTask { loadCategories() }
    }

    func loadCategories() {
        state.sheet?.categories = .loading
        let repository = repository
        bag.replace("categories") { [weak self] in
            let result = await attempt { try await repository.categories() }
            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let list): self.state.sheet?.categories = .ready(list)
            case .failure: self.state.sheet?.categories = .failed
            }
        }
    }

    func pickCategory(_ id: Int) {
        state.sheet?.target.categoryId = id
    }

    func closeSheet() {
        state.sheet = nil
    }

    /// The picker's result. An empty list means the person backed out, and the sheet stays.
    /// `target` is the sheet's, kept by the view while the picker covered it.
    func picked(_ files: [PickedFile], target: UploadTarget, single: Bool) {
        guard !files.isEmpty else { return }
        state.sheet = nil
        let chosen = single ? Array(files.prefix(1)) : files
        let repository = repository
        let id = taskId
        bag.run { await repository.add(taskId: id, files: chosen, target: target) }
    }

    func retry(_ id: String) {
        let repository = repository
        bag.run { await repository.retry(id) }
    }

    func dismiss(_ id: String) {
        let repository = repository
        bag.run { await repository.dismiss(id) }
    }

    private func settle(_ list: [TaskUpload]) {
        for done in list where done.state == .done && settling.insert(done.id).inserted {
            let clock = clock
            let repository = repository
            bag.run { [weak self] in
                try? await clock.sleep(for: Self.settleDelay)
                guard let self else { return }
                self.onFilesChanged()
                if done.requirementId != nil { self.loadRequired() }
                await repository.dismiss(done.id)
            }
        }
        // A requirement someone else filled meanwhile leaves the list; the row says why it failed.
        let filledElsewhere = list.contains {
            $0.problem == .alreadyFilled && $0.requirementId != nil && failuresSeen.insert($0.id).inserted
        }
        if filledElsewhere { loadRequired() }
    }

    private func rebuild() {
        let rows = uploads.map(UploadRow.init)
        var byRequirement: [Int: UploadRow] = [:]
        for (upload, row) in zip(uploads, rows) {
            if let requirement = upload.requirementId { byRequirement[requirement] = row }
        }
        var next = state
        next.required = required.map { files in
            files.map {
                RequiredRow(
                    id: $0.id,
                    name: $0.name,
                    isForm: $0.isForm,
                    removalPending: $0.removalPending,
                    upload: byRequirement[$0.id]
                )
            }
        }
        // A required file's upload shows on its row; once that requirement is gone (filled or
        // dropped meanwhile) it moves here, so a failure can still be read and dismissed.
        let listed = Set(required.value?.map(\.id) ?? [])
        let requiredLoaded = required.value != nil
        next.uploads = zip(uploads, rows).compactMap { upload, row in
            guard let requirement = upload.requirementId else { return row }
            return requiredLoaded && !listed.contains(requirement) ? row : nil
        }
        if next != state { state = next }
    }
}
