import Foundation

/// What a file's first bytes say it is, as sprout_web `fileSignatures` and the API read them.
public enum Sniffed: Sendable, Hashable {
    case pdf, png, jpeg, gif
    /// A photo format the server refuses (HEIC, WebP); the phone turns it into a JPG.
    case otherImage
    case unknown

    public var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .png: "png"
        case .jpeg, .otherImage: "jpg"
        case .gif: "gif"
        case .unknown: ""
        }
    }

    public var mimeType: String {
        switch self {
        case .pdf: "application/pdf"
        case .png: "image/png"
        case .jpeg, .otherImage: "image/jpeg"
        case .gif: "image/gif"
        case .unknown: "application/octet-stream"
        }
    }

    /// Sent as it is: a type the server takes.
    public var accepted: Bool { self == .pdf || self == .png || self == .jpeg || self == .gif }

    static let acceptedTypes: [Sniffed] = [.pdf, .png, .jpeg, .gif]
}

/// The web's upload rules (sprout_web `validateUploadFile`, sprout_api `TaskFileUploadSafetyPolicy`):
/// PDF, PNG, JPG or GIF by content, not empty, at most `maxBytes`. Photos the server can't take
/// are re-encoded as JPG, and so are photos over the limit, so a phone picture is never refused
/// for size. Mirrors Android `UploadChecks`.
public enum UploadChecks {
    public static let maxBytes: Int64 = 10 * 1_024 * 1_024
    public static let maxFiles = 10
    /// A photo up to eight times the limit is still read whole to shrink it; anything larger is
    /// refused before it is read.
    static let maxReadBytes: Int64 = 8 * maxBytes
    private static let maxStem = 120

    public enum Plan: Sendable, Hashable {
        case send
        case reencode
        case refuse(UploadProblem)
    }

    public static func sniff(_ data: Data) -> Sniffed {
        let header = [UInt8](data.prefix(16))
        if starts(header, [0x25, 0x50, 0x44, 0x46]) { return .pdf }
        if starts(header, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if starts(header, [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if starts(header, [0x47, 0x49, 0x46, 0x38]) { return .gif }
        if isHeif(header) || isWebp(header) { return .otherImage }
        return .unknown
    }

    /// What happens to a file of `size` bytes that sniffed as `type`.
    public static func plan(_ type: Sniffed, size: Int64) -> Plan {
        if size <= 0 { return .refuse(.empty) }
        switch type {
        case .unknown: return .refuse(.unsupported)
        case .otherImage: return .reencode
        default:
            guard size > maxBytes else { return .send }
            // A big photo shrinks to fit; a PDF or animated GIF can't, so the web's message applies.
            return type == .jpeg || type == .png ? .reencode : .refuse(.tooLarge)
        }
    }

    /// The picked name with the extension the content has, so the server's name check passes:
    /// "scan" or "scan.jpeg" from a PNG becomes "scan.png". Path parts and reserved characters go.
    public static func fileName(_ picked: String?, type: Sniffed, fallback: String) -> String {
        var base = picked ?? ""
        if let slash = base.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
            base = String(base[base.index(after: slash)...])
        }
        base = cleaned(base)
        if base.isEmpty { base = fallback }
        let (stem, ext) = split(base)
        var trimmedStem = String(stem.prefix(maxStem)).trimmingCharacters(in: .whitespaces)
        if trimmedStem.isEmpty { trimmedStem = fallback }
        let keeps = ext == type.fileExtension || (type == .jpeg && ext == "jpeg")
        return "\(trimmedStem).\(keeps ? ext : type.fileExtension)"
    }

    /// A template's name with the file's extension added, so "Signed plan" saves as
    /// "Signed plan.pdf" and the server's name check passes. A name that already ends in it is kept.
    public static func templateName(_ template: String, mimeType: String) -> String {
        guard let type = Sniffed.acceptedTypes.first(where: { $0.mimeType == mimeType }) else { return template }
        let name = String(cleaned(template).prefix(maxStem))
        guard !name.isEmpty else { return template }
        let lower = name.lowercased()
        let keeps = lower.hasSuffix(".\(type.fileExtension)") || (type == .jpeg && lower.hasSuffix(".jpeg"))
        return keeps ? name : "\(name).\(type.fileExtension)"
    }

    /// Reserved and control characters become dashes; surrounding spaces and dots go.
    private static func cleaned(_ text: String) -> String {
        let reserved: Set<Character> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]
        let mapped = String(
            text.map { character -> Character in
                if reserved.contains(character) { return "-" }
                if character.unicodeScalars.allSatisfy({ $0.value < 0x20 }) { return "-" }
                return character
            }
        )
        return mapped.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func split(_ name: String) -> (stem: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot > name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]).lowercased())
    }

    private static func starts(_ header: [UInt8], _ signature: [UInt8]) -> Bool {
        header.count >= signature.count && Array(header.prefix(signature.count)) == signature
    }

    private static let heifBrands: Set<String> = [
        "heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1", "avif",
    ]

    private static func ascii(_ header: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: header[range], as: UTF8.self)
    }

    private static func isHeif(_ header: [UInt8]) -> Bool {
        guard header.count >= 12, ascii(header, 4..<8) == "ftyp" else { return false }
        return heifBrands.contains(ascii(header, 8..<12))
    }

    private static func isWebp(_ header: [UInt8]) -> Bool {
        header.count >= 12 && ascii(header, 0..<4) == "RIFF" && ascii(header, 8..<12) == "WEBP"
    }
}
