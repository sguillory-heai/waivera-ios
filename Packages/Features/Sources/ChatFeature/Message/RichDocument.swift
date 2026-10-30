import Foundation
import WaiveraAPI
import WaiveraData

/// Inline marks the renderer understands (03 §7). Unknown marks are ignored.
enum RichMark: String, Hashable, Sendable, CaseIterable {
    case bold, italic, strike, underline, code
}

enum RichInline: Hashable, Sendable {
    /// `href` is set only for a link whose target passed `SafeLinks.url(_:)`.
    case text(String, marks: Set<RichMark> = [], href: URL? = nil)
    /// `@label`, falling back to the id, then "mention".
    case mention(String)
    case hardBreak
}

indirect enum RichBlock: Hashable, Sendable {
    case paragraph([RichInline])
    /// Level defaults to 2, as in the reference renderer.
    case heading(level: Int, [RichInline])
    /// Children render in the secondary colour.
    case blockquote([RichBlock])
    /// Ordered items show "N." with N = position + 1; bullet items show "•".
    case list(ordered: Bool, items: [[RichBlock]])
    case codeBlock(String)
    case horizontalRule
    /// Rows of cells; each cell holds blocks. Rendered in a horizontally scrolling grid.
    case table(rows: [[[RichBlock]]])
    /// An unknown node with content: its children render as blocks.
    case group([RichBlock])
}

struct RichDocument: Hashable, Sendable {
    var blocks: [RichBlock]
}

/// TipTap JSON to `RichDocument`. Mirrors the reference "onion peeler" so wrapped, stringified
/// and double-stringified documents all render (03 §7), and walks the tree recursively (11 §35).
/// Ported rule for rule from the Android `TipTapParser`, so both apps render the same.
enum TipTapParser {
    static let maxDepth = 10
    private static let editorMarker = "\"editor\""
    private static let preferredKeys = ["doc", "messageDoc", "content", "data", "value"]
    private static let inlineTypes: Set<String> = ["text", "mention", "hardBreak"]
    private static let lineTypes: Set<String> = [
        "paragraph", "heading", "blockquote", "listItem", "codeBlock", "tableRow",
    ]
    private static let defaultHeadingLevel = 2

    /// The rich document for `message`, or `nil` when it should render as plain text.
    static func document(for message: ChatMessage) -> RichDocument? {
        extractDoc(message.doc, text: message.content).map(parse)
    }

    /// Finds the first `{type: "doc", content: [...]}` in `doc`, else in `text` when it mentions
    /// an editor.
    static func extractDoc(_ doc: JSONValue?, text: String?) -> JSONValue? {
        if let found = find(doc, depth: 0) { return found }
        if let text, text.contains(editorMarker) {
            return find(.string(text), depth: 0)
        }
        return nil
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func find(_ payload: JSONValue?, depth: Int) -> JSONValue? {
        guard let payload, depth <= maxDepth else { return nil }
        switch payload {
        case .string(let raw):
            guard !raw.isEmpty, let parsed = safeJSONParse(raw) else { return nil }
            return find(parsed, depth: depth + 1)
        case .array(let values):
            for value in values {
                if let found = find(value, depth: depth + 1) { return found }
            }
            return nil
        case .object(let object):
            if object["type"]?.stringValue == "doc", object["content"]?.arrayValue != nil { return payload }
            for key in preferredKeys {
                guard let value = object[key], !value.isNull else { continue }
                if let found = find(value, depth: depth + 1) { return found }
            }
            // Dictionaries have no order; sorting keeps the search deterministic.
            for key in object.keys.sorted() where !preferredKeys.contains(key) {
                if let found = find(object[key], depth: depth + 1) { return found }
            }
            return nil
        case .null, .bool, .number:
            return nil
        }
    }

    /// `JSON.parse` after stripping one layer of surrounding quotes and un-escaping `\"`.
    static func safeJSONParse(_ value: String) -> JSONValue? {
        var clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count >= 2, clean.hasPrefix("\""), clean.hasSuffix("\"") {
            clean = String(clean.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        }
        return try? JSONDecoder().decode(JSONValue.self, from: Data(clean.utf8))
    }

    static func parse(_ doc: JSONValue) -> RichDocument {
        RichDocument(blocks: blocks(children(of: doc)))
    }

    private static func blocks(_ nodes: [JSONValue]) -> [RichBlock] {
        var result: [RichBlock] = []
        var pendingInline: [JSONValue] = []
        func flushInline() {
            guard !pendingInline.isEmpty else { return }
            result.append(.paragraph(inlines(pendingInline, inherited: [], inheritedHref: nil)))
            pendingInline.removeAll()
        }
        for node in nodes {
            if let type = node["type"]?.stringValue, inlineTypes.contains(type) {
                pendingInline.append(node)
                continue
            }
            flushInline()
            if let block = block(node) { result.append(block) }
        }
        flushInline()
        return result
    }

    // One case per TipTap node type; splitting the dispatch would only hide the list.
    // swiftlint:disable:next cyclomatic_complexity
    private static func block(_ node: JSONValue) -> RichBlock? {
        switch node["type"]?.stringValue {
        case "paragraph":
            return .paragraph(inlines(children(of: node), inherited: [], inheritedHref: nil))
        case "heading":
            let level = node["attrs"]?["level"]?.intValue ?? defaultHeadingLevel
            return .heading(level: level, inlines(children(of: node), inherited: [], inheritedHref: nil))
        case "blockquote":
            return .blockquote(blocks(children(of: node)))
        case "bulletList":
            return .list(ordered: false, items: listItems(node))
        case "orderedList":
            return .list(ordered: true, items: listItems(node))
        case "listItem":
            return .group(blocks(children(of: node)))
        case "codeBlock":
            return .codeBlock(children(of: node).map { plainText($0) }.joined())
        case "horizontalRule":
            return .horizontalRule
        case "table":
            let rows = children(of: node).filter { $0["type"]?.stringValue == "tableRow" }.map { row in
                children(of: row).map { cell in blocks(children(of: cell)) }
            }
            return .table(rows: rows)
        default:
            guard node["content"]?.arrayValue != nil else { return nil }
            return .group(blocks(children(of: node)))
        }
    }

    private static func listItems(_ node: JSONValue) -> [[RichBlock]] {
        children(of: node).map { child in
            if child["type"]?.stringValue == "listItem" { return blocks(children(of: child)) }
            return [block(child)].compactMap { $0 }
        }
    }

    private static func inlines(_ nodes: [JSONValue], inherited: Set<RichMark>, inheritedHref: URL?) -> [RichInline] {
        nodes.flatMap { node -> [RichInline] in
            switch node["type"]?.stringValue {
            case "text":
                let text = node["text"]?.stringValue ?? ""
                guard !text.isEmpty else { return [] }
                let (marks, href) = marks(of: node, inherited: inherited, inheritedHref: inheritedHref)
                return [.text(text, marks: marks, href: href)]
            case "mention":
                return [.mention(mentionLabel(node) ?? "mention")]
            case "hardBreak":
                return [.hardBreak]
            default:
                return inlines(children(of: node), inherited: inherited, inheritedHref: inheritedHref)
            }
        }
    }

    private static func marks(
        of node: JSONValue,
        inherited: Set<RichMark>,
        inheritedHref: URL?
    ) -> (Set<RichMark>, URL?) {
        var result = inherited
        var href = inheritedHref
        for mark in node["marks"]?.arrayValue ?? [] {
            switch mark["type"]?.stringValue {
            case "bold": result.insert(.bold)
            case "italic": result.insert(.italic)
            case "strike": result.insert(.strike)
            case "underline": result.insert(.underline)
            case "code": result.insert(.code)
            case "link": href = SafeLinks.url(mark["attrs"]?["href"]?.stringValue)
            default: break
            }
        }
        return (result, href)
    }

    private static func mentionLabel(_ node: JSONValue) -> String? {
        let attrs = node["attrs"]
        return attrs?["label"]?.stringValue ?? primitiveText(attrs?["id"])
    }

    /// Plain-text projection used for copy, edit and previews (03 §7), ported exactly.
    static func plainText(_ doc: JSONValue) -> String {
        nodePlainText(doc)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nodePlainText(_ node: JSONValue) -> String {
        let type = node["type"]?.stringValue
        switch type {
        case "text":
            return node["text"]?.stringValue ?? ""
        case "mention":
            return mentionLabel(node).map { "@\($0)" } ?? "@mention"
        case "hardBreak":
            return "\n"
        default:
            let text = children(of: node).map(nodePlainText).joined()
            if let type, lineTypes.contains(type) { return text + "\n" }
            return text
        }
    }

    private static func children(of node: JSONValue) -> [JSONValue] {
        (node["content"]?.arrayValue ?? []).filter { $0.objectValue != nil }
    }

    /// Any JSON primitive as text, the way `JsonPrimitive.content` reads it.
    private static func primitiveText(_ value: JSONValue?) -> String? {
        switch value {
        case .string(let text): return text
        case .number(let number):
            if number.rounded() == number, abs(number) < 9.0e15 { return String(Int64(number)) }
            return String(number)
        case .bool(let flag): return flag ? "true" : "false"
        default: return nil
        }
    }
}

extension ChatMessage {
    /// The text copied or edited: the document's plain text, else the stored text. Empty for a
    /// deleted message.
    var copyableText: String {
        guard !isDeleted else { return "" }
        if let doc = TipTapParser.extractDoc(doc, text: content) {
            return TipTapParser.plainText(doc)
        }
        return (plaintext ?? content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the bubble has text to render (an attachment-only bubble is transparent, 03 §6).
    var hasBody: Bool { !copyableText.isEmpty }
}
