import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Tapping a task file (Android `TaskFileActionsViewModel`). With the web's Download permission
/// for that kind of file (`case_file:download`, or `employee_file:download` for employee files) it
/// opens a sheet to view, save or share it, so nobody has to open a PDF just to keep a copy;
/// without it, the file simply opens.
@MainActor
@Observable
final class TaskFileActionsModel {
    enum Action: Sendable, Hashable { case save, share }

    /// The sheet a tapped file opens: what it is, and which action is running.
    /// Identified by the file, so a running action updates the open sheet instead of replacing it.
    struct Sheet: Identifiable, Sendable, Hashable {
        var row: FileRow
        var attachment: TaskAttachment
        var busy: Action?
        var id: Int { row.id }
    }

    /// A downloaded copy waiting for the system: the Files picker to save it, or the share sheet.
    /// Whoever presents it removes its folder when it closes.
    struct Handoff: Identifiable, Sendable, Hashable {
        var action: Action
        var url: URL
        var id: URL { url }
    }

    private(set) var sheet: Sheet?
    private(set) var handoff: Handoff?

    @ObservationIgnored let taskId: Int
    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private let feedback: TasksFeedback
    @ObservationIgnored private let bag = TaskBag()
    private static let running = "file-action"

    init(taskId: Int, environment: DataEnvironment, feedback: TasksFeedback) {
        self.taskId = taskId
        self.environment = environment
        self.feedback = feedback
    }

    /// Opens the sheet when the person may download this file; false means just open it.
    func choose(_ row: FileRow, attachment: TaskAttachment?, access: RequestAccess) -> Bool {
        // Too big to copy to the phone: it opens (on the web) as before.
        guard let attachment, attachment.sizeBytes <= TaskAttachment.maxExportBytes else { return false }
        let allowed = attachment.employeeFile ? access.canDownloadEmployeeFiles : access.canDownloadCaseFiles
        guard allowed else { return false }
        sheet = Sheet(row: row, attachment: attachment)
        return true
    }

    /// Closing the sheet also stops a download that is still running, so nothing pops up later.
    func dismiss() {
        bag.cancel(Self.running)
        if let handoff { Self.remove(handoff.url) }
        handoff = nil
        sheet = nil
    }

    /// Downloads the sheet's file once, then hands the copy to the system; one action at a time.
    func run(_ action: Action) {
        guard let current = sheet, current.busy == nil else { return }
        sheet?.busy = action
        let tasks = environment.tasks
        let taskId = taskId
        let file = current.attachment
        bag.replace(Self.running) { [weak self] in
            let result = await attempt { () async throws -> URL in
                let bytes = try await tasks.fileExport(taskId: taskId, attachment: file)
                return try Self.writeCopy(bytes, name: file.name)
            }
            guard let self, !Task.isCancelled else {
                if case .success(let url) = result { Self.remove(url) }
                return
            }
            switch result {
            case .success(let url):
                sheet?.busy = nil
                handoff = Handoff(action: action, url: url)
            case .failure:
                sheet?.busy = nil
                feedback.show(TasksStrings.text("tasks.file.downloadFailed"))
            }
        }
    }

    /// The Files picker finished: `picked` says whether the person chose a place.
    func saved(_ picked: Bool) {
        if picked { feedback.show(TasksStrings.text("tasks.file.saved")) }
    }

    /// The picker or share sheet closed: the copy has gone where it was sent, so the sheet closes
    /// too. The share sheet removes its own copy when it finishes.
    func handoffClosed() {
        guard let handoff else { return }
        if handoff.action == .save { Self.remove(handoff.url) }
        self.handoff = nil
        sheet = nil
    }

    /// A copy under the file's own name, in a folder of its own, protected while the phone is locked.
    nonisolated static func writeCopy(_ bytes: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(TaskFileModel.safeName(name))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #if os(iOS)
                try bytes.write(to: file, options: [.atomic, .completeFileProtection])
            #else
                try bytes.write(to: file, options: .atomic)
            #endif
            return file
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    nonisolated static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
