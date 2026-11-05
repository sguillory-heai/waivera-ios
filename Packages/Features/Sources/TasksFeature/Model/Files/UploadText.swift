import Foundation
import WaiveraData

/// The app's words for uploads; never the server's own text.
enum UploadText {
    static func problem(_ problem: UploadProblem?) -> String {
        let key: String =
            switch problem {
            case .empty: "tasks.upload.problem.empty"
            case .tooLarge: "tasks.upload.problem.tooLarge"
            case .unsupported, .mismatch: "tasks.upload.problem.type"
            case .pdfLocked: "tasks.upload.problem.pdfLocked"
            case .pdfUnreadable: "tasks.upload.problem.pdfUnreadable"
            case .alreadyFilled: "tasks.upload.problem.already"
            case .taskLocked: "tasks.upload.problem.locked"
            case .noAccess: "tasks.upload.problem.access"
            case .unreadable: "tasks.upload.problem.unreadable"
            case .failed, nil: "tasks.upload.problem.failed"
            }
        return TasksStrings.text(key)
    }

    /// The tone a row's note is drawn in.
    enum Tone: Hashable, Sendable { case secondary, success, danger, warning }

    struct Note: Hashable, Sendable {
        var text: String
        var tone: Tone
    }

    static func note(_ row: UploadRow) -> Note {
        switch row.state {
        case .queued: Note(text: TasksStrings.text("tasks.upload.waiting"), tone: .secondary)
        case .uploading: Note(text: TasksStrings.text("tasks.upload.starting"), tone: .secondary)
        case .done: Note(text: TasksStrings.text("tasks.upload.done"), tone: .success)
        case .failed: Note(text: TasksStrings.format("tasks.upload.failed", problem(row.problem)), tone: .danger)
        }
    }

    static func note(_ row: RequiredRow) -> Note {
        if row.isForm { return Note(text: TasksStrings.text("tasks.required.form"), tone: .secondary) }
        if let upload = row.upload { return note(upload) }
        if row.removalPending { return Note(text: TasksStrings.text("tasks.required.removal"), tone: .secondary) }
        return Note(text: TasksStrings.text("tasks.required.needed"), tone: .warning)
    }

    static func name(_ row: UploadRow) -> String {
        row.name.isEmpty ? TasksStrings.text("tasks.upload.unnamed") : row.name
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
