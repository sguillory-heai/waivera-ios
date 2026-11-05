import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// What the viewer shows once the file is on the phone. Bytes stay in memory only.
enum FileContent: Equatable, Sendable {
    case text(String, cut: Bool)
    case image(Data)
    case pdf(Data)
    case word([WordBlock])
}

enum FilePhase: Equatable, Sendable {
    case loading
    /// Couldn't download or read it; the web can still open it.
    case failed
    case ready(FileContent)
}

/// One file in the task's Files section, already worded.
struct FileRow: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var kind: FileKind
    var size: String
    var added: String?
    var addedBy: String?
    var viewable: Bool

    var short: String { Self.short(kind) }

    static func short(_ kind: FileKind) -> String {
        switch kind {
        case .pdf: TasksStrings.text("tasks.file.short.pdf")
        case .image: TasksStrings.text("tasks.file.short.image")
        case .word: TasksStrings.text("tasks.file.short.word")
        case .text: TasksStrings.text("tasks.file.short.text")
        case .other: TasksStrings.text("tasks.file.short.other")
        }
    }

    var kindLabel: String {
        switch kind {
        case .pdf: TasksStrings.text("tasks.file.kind.pdf")
        case .image: TasksStrings.text("tasks.file.kind.image")
        case .word: TasksStrings.text("tasks.file.kind.word")
        case .text: TasksStrings.text("tasks.file.kind.text")
        case .other: TasksStrings.text("tasks.file.kind.other")
        }
    }

    /// Type, size and date fit on one line; the person who added it gets its own.
    var meta: String { [kindLabel, size, added].compactMap(\.self).joined(separator: " · ") }

    /// Why it opens on the web instead, or nil when the phone shows it.
    var webNote: String? {
        if viewable { return nil }
        return TasksStrings.text(kind == .other ? "tasks.file.opensOnWeb" : "tasks.file.tooLarge")
    }

    var accessibilityLabel: String {
        [name, meta, addedBy.map { TasksStrings.format("tasks.file.addedBy", $0) }, webNote]
            .compactMap(\.self).joined(separator: ", ")
    }

    static func make(_ attachment: TaskAttachment, zone: TimeZone, today: CalendarDate) -> FileRow {
        FileRow(
            id: attachment.attachmentId,
            name: attachment.name,
            kind: attachment.kind,
            size: ByteCountFormatter.string(fromByteCount: attachment.sizeBytes, countStyle: .file),
            added: attachment.addedAt.map { TaskFormat.date(CalendarDate($0, in: zone), today: today) },
            addedBy: attachment.addedBy,
            viewable: attachment.viewable
        )
    }
}

/// A task file, read-only (Android `TaskFileViewModel`): fetched into memory, turned into
/// something to show, and dropped when the viewer closes. Nothing is written to disk.
@MainActor
@Observable
final class TaskFileModel {
    nonisolated static let maxTextBytes = 512 * 1024

    private(set) var name = ""
    private(set) var kind: FileKind?
    private(set) var phase = FilePhase.loading
    /// The file's bytes once shown, for Share or save.
    private(set) var bytes: Data?

    @ObservationIgnored let taskId: Int
    @ObservationIgnored let attachmentId: Int
    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private var webPath: String?

    init(taskId: Int, attachmentId: Int, environment: DataEnvironment) {
        self.taskId = taskId
        self.attachmentId = attachmentId
        self.environment = environment
    }

    /// Loads (or reloads after a failure). The view runs it in its task, so leaving cancels it.
    func load() async {
        phase = .loading
        let tasks = environment.tasks
        let taskId = taskId
        let attachmentId = attachmentId
        if webPath == nil { webPath = (try? await tasks.task(id: taskId))?.webPath }
        let found = await attempt { try await tasks.attachments(taskId: taskId) }
        guard case .success(let files) = found, let file = files.first(where: { $0.attachmentId == attachmentId })
        else {
            phase = .failed
            return
        }
        name = file.name
        kind = file.kind
        guard file.viewable else {
            phase = .failed
            return
        }
        let data = await attempt { try await tasks.fileData(taskId: taskId, attachment: file) }
        guard !Task.isCancelled else { return }
        guard case .success(let bytes) = data, let content = await Self.read(bytes, kind: file.kind) else {
            phase = .failed
            return
        }
        self.bytes = bytes
        phase = .ready(content)
    }

    /// A copy under the file's own name for the share sheet, in a folder of its own that the
    /// sheet removes when it closes (Android `TaskFileExport`).
    func exportCopy() -> URL? {
        guard let bytes else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = folder.appendingPathComponent(Self.safeName(name))
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
            return nil
        }
    }

    /// The task on the web, where every file opens; nil when no web app is configured.
    var webURL: URL? {
        webPath.flatMap { TasksWeb.url($0, base: environment.webBaseURL) }
    }

    /// A file name any app accepts: no path characters, never empty or dots alone.
    nonisolated static func safeName(_ name: String) -> String {
        let blocked = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        let cleaned = String(name.unicodeScalars.map { blocked.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxNameLength)
        return cleaned.isEmpty || cleaned.allSatisfy { $0 == "." } ? "file" : String(cleaned)
    }

    nonisolated static let maxNameLength = 120

    /// Off the main actor: inflating and parsing a Word file can take a moment.
    @concurrent
    nonisolated static func read(_ bytes: Data, kind: FileKind) async -> FileContent? {
        switch kind {
        case .text: return text(bytes)
        case .image: return .image(bytes)
        case .pdf: return bytes.starts(with: Array("%PDF".utf8)) ? .pdf(bytes) : nil
        case .word: return (try? DocxReader.blocks(from: bytes)).map(FileContent.word)
        case .other: return nil
        }
    }

    /// The first 512 KB, cut back to a whole UTF-8 character.
    nonisolated static func text(_ bytes: Data) -> FileContent {
        let all = [UInt8](bytes)
        let cut = all.count > maxTextBytes
        var end = min(all.count, maxTextBytes)
        if cut { while end > 0, all[end] & 0xC0 == 0x80 { end -= 1 } }
        return .text(String(decoding: all[0..<end], as: UTF8.self), cut: cut)
    }
}

/// How long the note's open and close take: a short move is quick and a long one is not
/// rushed (Android `WaiveraMotionScheme.expand`).
enum NoteMotion {
    static func duration(distance: CGFloat) -> Double {
        let millis = (180 + distance * 0.5).rounded()
        return min(max(millis, 180), 480) / 1_000
    }
}
