import Foundation
import WaiveraAPI
import WaiveraData

/// Uploads that land after a short pause, with the demo task's required files. Every step can be
/// made to fail or to refuse a file.
public final class FakeTaskUploadsRepository: TaskUploadsRepository, @unchecked Sendable {
    public let failure = LockedValue<WaiveraError?>(nil)
    /// The next added or sent file is refused with this reason.
    public let nextProblem = LockedValue<UploadProblem?>(nil)
    /// Uploads stay queued until this is false, so tests can look at them in flight.
    public let holds = LockedValue(false)
    public let required: LockedValue<[Int: [RequiredFile]]>
    /// Every file sent now, with the name it went under.
    public let sentNow = LockedValue<[String]>([])
    public let discarded = LockedValue<[PreparedFile]>([])
    /// Late-reason evidence sent, by file name; each gets the next attachment id from 900.
    public let evidenceSent = LockedValue<[String]>([])
    private let cell = StateCell<[TaskUpload]>([])
    private let clock: any WaiveraClock

    public init(empty: Bool = false, clock: any WaiveraClock = SystemClock()) {
        self.clock = clock
        required = LockedValue(empty ? [:] : [12: Self.demoRequired])
    }

    public static let demoRequired = [
        RequiredFile(id: 41, name: "Signed care plan", typeId: 3),
        RequiredFile(id: 42, name: "Annual assessment", typeId: 5, formName: "Annual assessment"),
    ]

    public func uploads(taskId: Int) -> AsyncStream<[TaskUpload]> {
        let source = cell.stream()
        return AsyncStream { continuation in
            let task = Task {
                for await list in source { continuation.yield(list.filter { $0.taskId == taskId }) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func requiredFiles(taskId: Int) async throws -> [RequiredFile] {
        if let failure = failure.get() { throw failure }
        return required.get()[taskId] ?? []
    }

    public func categories() async throws -> [DocumentCategory] {
        if let failure = failure.get() { throw failure }
        return [DocumentCategory(id: 1, name: "Certifications"), DocumentCategory(id: 2, name: "Training")]
    }

    public func add(taskId: Int, files: [PickedFile], target: UploadTarget) async {
        for (index, file) in files.prefix(UploadChecks.maxFiles).enumerated() {
            let id = UUID().uuidString
            let problem = nextProblem.update { value -> UploadProblem? in
                defer { value = nil }
                return value
            }
            let name = Self.name(file) ?? target.requirementName ?? "upload-\(index + 1).jpg"
            let upload = TaskUpload(
                id: id,
                taskId: taskId,
                fileName: name,
                kind: FileKind(name: name, mimeType: nil),
                sizeBytes: Self.size(file),
                requirementId: target.requirementId,
                state: problem == nil ? .queued : .failed,
                problem: problem
            )
            cell.update { $0.append(upload) }
            if problem == nil { land(id) }
        }
    }

    public func retry(_ id: String) async {
        cell.update { list in
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            list[index].state = .queued
            list[index].problem = nil
        }
        land(id)
    }

    public func dismiss(_ id: String) async {
        cell.update { $0.removeAll { $0.id == id } }
    }

    public func prepare(_ file: PickedFile, purpose: PickPurpose) async throws -> PreparedFile {
        if let problem = nextProblem.update({ value -> UploadProblem? in
            defer { value = nil }
            return value
        }) {
            throw UploadRefused(problem, pickedName: Self.name(file))
        }
        let name = Self.name(file) ?? "upload.jpg"
        let mime = name.lowercased().hasSuffix(".pdf") ? "application/pdf" : "image/jpeg"
        return PreparedFile(path: "/fake/\(name)", name: name, mimeType: mime, sizeBytes: Self.size(file))
    }

    public func sendNow(taskId: Int, file: PreparedFile, template: FileTemplate?) async throws -> String? {
        if let failure = failure.get() { throw UploadRefused(failure.isTransient ? .failed : .noAccess) }
        let name = template.map { UploadChecks.templateName($0.name, mimeType: file.mimeType) } ?? file.name
        sentNow.update { $0.append(name) }
        return name
    }

    public func sendEvidence(taskId: Int, file: PreparedFile) async throws -> Int {
        if let failure = failure.get() { throw UploadRefused(failure.isTransient ? .failed : .noAccess) }
        return evidenceSent.update { sent -> Int in
            sent.append(file.name)
            return 899 + sent.count
        }
    }

    public func discard(_ file: PreparedFile) async {
        discarded.update { $0.append(file) }
    }

    private func land(_ id: String) {
        let clock = clock
        Task { [cell, holds] in
            cell.update { list in
                if let index = list.firstIndex(where: { $0.id == id }) { list[index].state = .uploading }
            }
            try? await clock.sleep(for: .milliseconds(600))
            while holds.get() { try? await clock.sleep(for: .milliseconds(50)) }
            cell.update { list in
                if let index = list.firstIndex(where: { $0.id == id }) { list[index].state = .done }
            }
        }
    }

    private static func name(_ file: PickedFile) -> String? {
        switch file {
        case .url(let url): return url.lastPathComponent
        case .data(_, let name): return name
        }
    }

    private static func size(_ file: PickedFile) -> Int64 {
        switch file {
        case .url: 120_000
        case .data(let data, _): Int64(data.count)
        }
    }
}
