import Foundation
import WaiveraAPI

/// Files going onto tasks (Android `TaskUploadRepository`). Picked files are checked and copied
/// into app storage at once, then sent one at a time while the app runs; a file still queued when
/// the app closes goes up the next time it opens, and a dropped connection retries with backoff.
/// Sign-out drops everything still queued.
public protocol TaskUploadsRepository: Sendable {
    /// This task's uploads the server does not list yet, oldest first.
    func uploads(taskId: Int) -> AsyncStream<[TaskUpload]>
    /// The task's required files still missing.
    func requiredFiles(taskId: Int) async throws -> [RequiredFile]
    /// Employee file categories, for an extra file on an employee task.
    func categories() async throws -> [DocumentCategory]
    /// Checks and queues `files`, at most ten. A file that fails the web's checks (type, size,
    /// empty) is listed as failed with its reason and is not sent.
    func add(taskId: Int, files: [PickedFile], target: UploadTarget) async
    /// Sends a failed upload again.
    func retry(_ id: String) async
    /// Forgets an upload: a failed one the person dismissed, or a finished one the server now lists.
    func dismiss(_ id: String) async
    /// Checks and copies a file picked for Log activity; throws `UploadRefused`. Only the latest
    /// prepared file is kept.
    func prepare(_ file: PickedFile) async throws -> PreparedFile
    /// Sends `file` now, under `template`'s name and type when there is one (sprout_web logs the
    /// activity only after its file is up). Returns the name the server saved it as; throws
    /// `UploadRefused`.
    func sendNow(taskId: Int, file: PreparedFile, template: FileTemplate?) async throws -> String?
    /// Drops a prepared file the person removed or never sent.
    func discard(_ file: PreparedFile) async
}

/// One queued upload as stored on disk.
struct UploadEntry: Codable, Sendable, Hashable {
    var id: String
    var taskId: Int
    var localPath: String?
    var fileName: String
    var mimeType: String
    var sizeBytes: Int64 = 0
    var target: UploadTarget
    var state: UploadState = .queued
    var problem: UploadProblem?
    var savedName: String?
    var createdAt: Date
    /// A send failed after it may have reached the server; a resend that says "already
    /// uploaded" then counts as done.
    var mayHaveLanded = false
}

public actor LiveTaskUploadsRepository: TaskUploadsRepository {
    static let backoffStart: Duration = .seconds(10)
    static let backoffMax: Duration = .seconds(300)
    private static let queueFile = "queue.json"

    private let api: APIClient
    private let clock: any WaiveraClock
    private let root: URL
    private let stager = UploadStager()
    private let entries = StateCell<[UploadEntry]>([])
    private var loaded = false
    private var pump: Task<Void, Never>?
    private var backoff: Task<Void, Never>?
    private var failures = 0
    /// Bumped by sign-out: a copy or send that finishes afterwards never lands for the next account.
    private var generation = 0

    /// `root` holds the queue and its copies; by default Application Support/TaskUploads.
    public init(api: APIClient, clock: any WaiveraClock, root: URL? = nil) {
        self.api = api
        self.clock = clock
        self.root = root ?? Self.defaultRoot()
    }

    static func defaultRoot() -> URL {
        let support =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("TaskUploads", isDirectory: true)
    }

    private var stagingDirectory: URL { root.appendingPathComponent("queued", isDirectory: true) }
    private var activityDirectory: URL { root.appendingPathComponent("activity", isDirectory: true) }

    // MARK: Reading

    public nonisolated func uploads(taskId: Int) -> AsyncStream<[TaskUpload]> {
        let source = entries.stream()
        return AsyncStream { continuation in
            let task = Task {
                await self.resume()
                var last: [TaskUpload]?
                for await list in source {
                    let mine = list.filter { $0.taskId == taskId }
                        .sorted { $0.createdAt < $1.createdAt }
                        .map(Self.upload)
                    if mine != last {
                        last = mine
                        continuation.yield(mine)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func requiredFiles(taskId: Int) async throws -> [RequiredFile] {
        try await api.requiredAttachments(taskId: taskId).compactMap(UploadMapping.required)
    }

    public func categories() async throws -> [DocumentCategory] {
        try await api.documentCategories().compactMap(UploadMapping.category)
    }

    // MARK: Queue

    public func add(taskId: Int, files: [PickedFile], target: UploadTarget) async {
        loadIfNeeded()
        let started = generation
        for file in files.prefix(UploadChecks.maxFiles) {
            let entry = stage(file, taskId: taskId, target: target)
            // A sign-out while copying: drop this copy and the rest.
            guard generation == started else {
                if let path = entry.localPath { try? FileManager.default.removeItem(atPath: path) }
                return
            }
            change { $0.append(entry) }
        }
        startPump()
    }

    public func retry(_ id: String) async {
        loadIfNeeded()
        change { list in
            guard let index = list.firstIndex(where: { $0.id == id }), list[index].state == .failed,
                list[index].problem?.canRetry == true
            else { return }
            list[index].state = .queued
            list[index].problem = nil
        }
        failures = 0
        startPump()
    }

    public func dismiss(_ id: String) async {
        loadIfNeeded()
        change { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            if let path = list[index].localPath { try? FileManager.default.removeItem(atPath: path) }
            list.remove(at: index)
        }
    }

    /// The app came to the front or the connection came back: send what is waiting now, without
    /// waiting out the backoff.
    public func resume() {
        loadIfNeeded()
        guard entries.current.contains(where: { $0.state == .queued }) else { return }
        backoff?.cancel()
        backoff = nil
        startPump()
    }

    /// Sign-out: nothing queued may go up under the next account.
    public func clear() {
        generation += 1
        pump?.cancel()
        pump = nil
        backoff?.cancel()
        backoff = nil
        failures = 0
        entries.set([])
        loaded = true
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Log activity's file

    public func prepare(_ file: PickedFile) async throws -> PreparedFile {
        // One Log activity sheet is open at a time; an earlier pick it never sent goes.
        try? FileManager.default.removeItem(at: activityDirectory)
        let staged = try stager.stage(file, into: activityDirectory)
        return PreparedFile(
            path: staged.path,
            name: staged.fileName,
            mimeType: staged.mimeType,
            sizeBytes: staged.sizeBytes
        )
    }

    public func sendNow(taskId: Int, file: PreparedFile, template: FileTemplate?) async throws -> String? {
        guard let data = FileManager.default.contents(atPath: file.path) else { throw UploadRefused(.unreadable) }
        let name = template.map { UploadChecks.templateName($0.name, mimeType: file.mimeType) } ?? file.name
        let form = TaskUploadForm(
            data: data,
            fileName: name,
            savedName: name,
            taskId: taskId,
            typeId: template?.typeId ?? UploadTarget.plainTypeId,
            requirementId: nil,
            categoryId: template?.categoryId,
            mimeType: file.mimeType
        )
        do {
            let saved = try await api.uploadTaskFile(form)
            try? FileManager.default.removeItem(atPath: file.path)
            return saved.fileName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        } catch {
            throw UploadRefused(UploadMapping.problem(error))
        }
    }

    public func discard(_ file: PreparedFile) async {
        try? FileManager.default.removeItem(atPath: file.path)
    }

    // MARK: Sending

    private func startPump() {
        guard pump == nil, backoff == nil else { return }
        pump = Task { await self.drain() }
    }

    private func drain() async {
        let started = generation
        while !Task.isCancelled, generation == started,
            let next = entries.current.first(where: { $0.state == .queued })
        {
            let delivered = await send(next, generation: started)
            guard generation == started else { return }
            if !delivered {
                pump = nil
                scheduleRetry()
                return
            }
        }
        if generation == started { pump = nil }
    }

    /// False when the connection failed and the entry went back in line.
    private func send(_ entry: UploadEntry, generation started: Int) async -> Bool {
        guard let path = entry.localPath, let data = FileManager.default.contents(atPath: path) else {
            update(entry.id) {
                $0.state = .failed
                $0.problem = .unreadable
            }
            return true
        }
        update(entry.id) {
            $0.state = .uploading
            $0.problem = nil
        }
        let form = TaskUploadForm(
            data: data,
            fileName: entry.fileName,
            savedName: entry.target.requirementName ?? entry.fileName,
            taskId: entry.taskId,
            typeId: entry.target.typeId,
            requirementId: entry.target.requirementId,
            categoryId: entry.target.categoryId,
            mimeType: entry.mimeType
        )
        do {
            let saved = try await api.uploadTaskFile(form)
            guard generation == started else { return true }
            failures = 0
            try? FileManager.default.removeItem(atPath: path)
            update(entry.id) {
                $0.state = .done
                $0.localPath = nil
                $0.savedName = saved.fileName.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            }
            return true
        } catch {
            guard generation == started else { return true }
            return settle(entry, error: error)
        }
    }

    /// A dropped connection puts the file back in line (false); anything else fails it with a reason.
    private func settle(_ entry: UploadEntry, error: any Error) -> Bool {
        let mapped = WaiveraError.from(error)
        if Task.isCancelled || mapped.isTransient {
            // The send may have reached the server before the connection went.
            update(entry.id) {
                $0.state = .queued
                $0.mayHaveLanded = true
            }
            return false
        }
        let problem = UploadMapping.problem(error)
        update(entry.id) {
            if problem == .alreadyFilled && $0.mayHaveLanded {
                $0.state = .done
            } else {
                $0.state = .failed
                $0.problem = problem
            }
        }
        return true
    }

    private func scheduleRetry() {
        failures += 1
        let exponent = min(failures - 1, 5)
        let wait = min(Self.backoffStart * (1 << exponent), Self.backoffMax)
        let clock = clock
        backoff = Task {
            try? await clock.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self.backoffEnded()
        }
    }

    private func backoffEnded() {
        backoff = nil
        startPump()
    }

    // MARK: Storage

    private func stage(_ file: PickedFile, taskId: Int, target: UploadTarget) -> UploadEntry {
        let id = UUID().uuidString
        do {
            let staged = try stager.stage(file, into: stagingDirectory)
            return UploadEntry(
                id: id,
                taskId: taskId,
                localPath: staged.path,
                fileName: staged.fileName,
                mimeType: staged.mimeType,
                sizeBytes: staged.sizeBytes,
                target: target,
                createdAt: clock.now
            )
        } catch {
            let refused = error as? UploadRefused
            return UploadEntry(
                id: id,
                taskId: taskId,
                fileName: refused?.pickedName ?? target.requirementName ?? "",
                mimeType: "",
                target: target,
                state: .failed,
                problem: refused?.problem ?? .unreadable,
                createdAt: clock.now
            )
        }
    }

    private func update(_ id: String, _ edit: (inout UploadEntry) -> Void) {
        change { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            edit(&list[index])
        }
    }

    private func change(_ edit: (inout [UploadEntry]) -> Void) {
        let list = entries.update(edit)
        save(list)
    }

    /// Reads the queue once. A file that was sending when the app closed goes back in line.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let url = root.appendingPathComponent(Self.queueFile, isDirectory: false)
        guard let data = FileManager.default.contents(atPath: url.path),
            var list = try? JSONDecoder().decode([UploadEntry].self, from: data)
        else { return }
        for index in list.indices where list[index].state == .uploading {
            list[index].state = .queued
            list[index].mayHaveLanded = true
        }
        entries.set(list)
    }

    private func save(_ list: [UploadEntry]) {
        do {
            try UploadFiles.prepare(root)
            let data = try JSONEncoder().encode(list)
            try UploadFiles.write(data, to: root.appendingPathComponent(Self.queueFile, isDirectory: false))
        } catch {
            // The queue still works for this run; only surviving a restart is lost.
        }
    }

    private static func upload(_ entry: UploadEntry) -> TaskUpload {
        TaskUpload(
            id: entry.id,
            taskId: entry.taskId,
            fileName: entry.savedName ?? entry.fileName,
            kind: FileKind(name: entry.fileName, mimeType: entry.mimeType),
            sizeBytes: entry.sizeBytes,
            requirementId: entry.target.requirementId,
            state: entry.state,
            problem: entry.problem,
            savedName: entry.savedName
        )
    }
}

/// No uploads: for previews and environments that have no task server.
public struct EmptyTaskUploadsRepository: TaskUploadsRepository {
    public init() {}

    public func uploads(taskId: Int) -> AsyncStream<[TaskUpload]> {
        AsyncStream { continuation in
            continuation.yield([])
            continuation.finish()
        }
    }
    public func requiredFiles(taskId: Int) async throws -> [RequiredFile] { [] }
    public func categories() async throws -> [DocumentCategory] { [] }
    public func add(taskId: Int, files: [PickedFile], target: UploadTarget) async {}
    public func retry(_ id: String) async {}
    public func dismiss(_ id: String) async {}
    public func prepare(_ file: PickedFile) async throws -> PreparedFile { throw UploadRefused(.failed) }
    public func sendNow(taskId: Int, file: PreparedFile, template: FileTemplate?) async throws -> String? {
        throw UploadRefused(.failed)
    }
    public func discard(_ file: PreparedFile) async {}
}
