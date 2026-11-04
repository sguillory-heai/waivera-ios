import Foundation

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// One block of a Word document as the viewer shows it: plain text, no styling beyond headings
/// and list items. Pictures and links are left out (the link's text stays).
struct WordBlock: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case paragraph
        case heading(Int)
        case listItem
    }

    var kind: Kind
    var text: String
}

/// Reads a .docx as simple text: the ZIP's `word/document.xml`, inflated in memory and walked
/// paragraph by paragraph. Anything it cannot read (encrypted, ZIP64, not a .docx) fails, and the
/// viewer offers the web instead.
enum DocxReader {
    enum Failure: Error { case notDocx }

    /// The uncompressed document part may be this large; the file itself is capped at 20 MB.
    static let maxDocumentBytes = 32 * 1024 * 1024

    static func blocks(from data: Data) throws -> [WordBlock] {
        let xml = try ZipArchive(data).entry(named: "word/document.xml", limit: maxDocumentBytes)
        let walker = DocumentWalker()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = walker
        guard parser.parse() else { throw Failure.notDocx }
        return walker.blocks
    }
}

/// Just enough ZIP to find one entry by name: the end record, the central directory and the
/// entry's local header. Stored and deflated entries only.
struct ZipArchive {
    private let bytes: [UInt8]

    init(_ data: Data) { bytes = [UInt8](data) }

    private func u16(_ offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }

    private func u32(_ offset: Int) -> Int? {
        guard let low = u16(offset), let high = u16(offset + 2) else { return nil }
        return low | high << 16
    }

    func entry(named name: String, limit: Int) throws -> Data {
        guard let end = endRecord(), let count = u16(end + 10), let directory = u32(end + 16) else {
            throw DocxReader.Failure.notDocx
        }
        var offset = directory
        for _ in 0..<count {
            guard u32(offset) == 0x0201_4B50, let flags = u16(offset + 8), let method = u16(offset + 10),
                let compressed = u32(offset + 20), let size = u32(offset + 24), let nameLength = u16(offset + 28),
                let extraLength = u16(offset + 30), let commentLength = u16(offset + 32),
                let local = u32(offset + 42), offset + 46 + nameLength <= bytes.count
            else { throw DocxReader.Failure.notDocx }
            let entryName = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            if entryName == name {
                // Encrypted entries, and ZIP64 sizes, are not something a Word upload should need.
                guard flags & 1 == 0, compressed != 0xFFFF_FFFF, size <= limit else {
                    throw DocxReader.Failure.notDocx
                }
                return try read(local: local, method: method, compressed: compressed, limit: limit)
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        throw DocxReader.Failure.notDocx
    }

    private func endRecord() -> Int? {
        let earliest = max(0, bytes.count - 22 - 0xFFFF)
        var offset = bytes.count - 22
        while offset >= earliest {
            if u32(offset) == 0x0605_4B50 { return offset }
            offset -= 1
        }
        return nil
    }

    private func read(local: Int, method: Int, compressed: Int, limit: Int) throws -> Data {
        guard u32(local) == 0x0403_4B50, let nameLength = u16(local + 26), let extraLength = u16(local + 28) else {
            throw DocxReader.Failure.notDocx
        }
        let start = local + 30 + nameLength + extraLength
        guard start + compressed <= bytes.count else { throw DocxReader.Failure.notDocx }
        let body = Data(bytes[start..<(start + compressed)])
        switch method {
        case 0: return body
        case 8: return try Inflate.decompress(body, limit: limit)
        default: throw DocxReader.Failure.notDocx
        }
    }
}

/// Collects paragraphs from WordprocessingML. Text only counts inside `w:t`, so field codes and
/// deleted text stay out.
private final class DocumentWalker: NSObject, XMLParserDelegate {
    private(set) var blocks: [WordBlock] = []
    private var text = ""
    private var kind = WordBlock.Kind.paragraph
    private var inParagraph = false
    private var inText = false
    private var inProperties = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "w:p":
            inParagraph = true
            text = ""
            kind = .paragraph
        case "w:pPr": inProperties = true
        case "w:pStyle" where inProperties:
            kind = Self.kind(style: attributes["w:val"] ?? "", current: kind)
        case "w:numPr" where inProperties:
            if kind == .paragraph { kind = .listItem }
        case "w:t": inText = true
        case "w:tab" where inParagraph && !inProperties: text += "\t"
        case "w:br", "w:cr": if inParagraph { text += "\n" }
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "w:t": inText = false
        case "w:pPr": inProperties = false
        case "w:p":
            inParagraph = false
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { blocks.append(WordBlock(kind: kind, text: trimmed)) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { text += string }
    }

    /// "Heading1"…"Heading6" (and "Title") become headings; a list style makes a list item.
    static func kind(style: String, current: WordBlock.Kind) -> WordBlock.Kind {
        let lowered = style.lowercased()
        if lowered == "title" { return .heading(1) }
        if lowered.hasPrefix("heading"), let level = Int(lowered.dropFirst("heading".count)), (1...6).contains(level) {
            return .heading(level)
        }
        if lowered.contains("list") { return .listItem }
        return current
    }
}
