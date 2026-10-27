import Foundation
import WaiveraData

enum FileKind: Hashable, Sendable {
    case spreadsheet, document, other

    var systemImage: String {
        switch self {
        case .spreadsheet: "tablecells"
        case .document: "doc.text"
        case .other: "doc"
        }
    }
}

/// Attachment rules from 03 §8, kept free of UIKit so they are unit tested.
enum AttachmentRules {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif"]
    static let defaultMimeType = "application/octet-stream"
    static let maxFileNameLength = 120
    private static let mimeTypes = [
        "pdf": "application/pdf",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "xls": "application/vnd.ms-excel",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "doc": "application/msword",
        "txt": "text/plain",
        "csv": "text/csv",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "heic": "image/heic",
    ]

    static func isImage(_ attachment: Attachment) -> Bool {
        if attachment.kind == .image { return true }
        let contentType = attachment.contentType?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        if contentType.hasPrefix("image/") || imageExtensions.contains(contentType) { return true }
        return false
    }

    /// The name shown and saved: the original name, else `waivera-attachment-<id>.<ext>`.
    static func fileName(_ attachment: Attachment, messageId: Int) -> String {
        if let name = attachment.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return "waivera-attachment-\(max(messageId, 0)).\(fileExtension(forType: typeHint(attachment)))"
    }

    /// The type if it is a MIME type, else inferred from the file name, else octet-stream.
    static func mimeType(_ attachment: Attachment, messageId: Int) -> String {
        if let contentType = attachment.contentType, contentType.contains("/") { return contentType }
        let name = fileName(attachment, messageId: messageId)
        let ext = name.contains(".") ? (name.split(separator: ".").last.map { String($0).lowercased() } ?? "") : ""
        return mimeTypes[ext] ?? defaultMimeType
    }

    static func kind(_ attachment: Attachment, messageId: Int) -> FileKind {
        let hint = (typeHint(attachment) + " " + fileName(attachment, messageId: messageId)).lowercased()
        if ["xls", "excel", "spreadsheet", "csv"].contains(where: hint.contains) { return .spreadsheet }
        if ["pdf", "doc", "word"].contains(where: hint.contains) { return .document }
        return .other
    }

    /// A file-system-safe name for the share and save copies: reserved characters become `-`,
    /// whitespace collapses, at most 120 characters (03 §8).
    static func sanitizedFileName(_ name: String) -> String {
        let reserved = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let replaced = String(name.unicodeScalars.map { reserved.contains($0) ? "-" : Character($0) })
        let collapsed = replaced.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let trimmed = String(collapsed.prefix(maxFileNameLength)).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "attachment" : trimmed
    }

    private static func typeHint(_ attachment: Attachment) -> String {
        (attachment.contentType ?? "").lowercased()
    }

    private static func fileExtension(forType type: String) -> String {
        if type.contains("pdf") { return "pdf" }
        if type.contains("excel") || type.contains("spreadsheet") { return "xlsx" }
        if type.contains("word") || type.contains("document") { return "docx" }
        if type.contains("text") { return "txt" }
        return "bin"
    }
}
