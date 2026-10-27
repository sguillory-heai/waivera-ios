import Foundation
import WaiveraAPI

/// TipTap document helpers shared by previews, search, banners and the outgoing composer
/// (03 §7, §11). Rendering lives in the conversation feature; this is text only.
public enum RichText {
    /// The plain-text projection of a TipTap doc: paragraphs and hard breaks become newlines,
    /// mentions become `@label`.
    public static func plainText(_ doc: JSONValue?) -> String? {
        guard let doc, doc["type"]?.stringValue == "doc" || doc["content"] != nil else { return nil }
        var blocks: [String] = []
        for block in doc["content"]?.arrayValue ?? [] {
            blocks.append(inlineText(block))
        }
        let text = blocks.joined(separator: "\n")
        let collapsed = text.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        let result = collapsed.trimmed
        return result.isEmpty ? nil : result
    }

    private static func inlineText(_ node: JSONValue) -> String {
        switch node["type"]?.stringValue {
        case "text":
            return node["text"]?.stringValue ?? ""
        case "hardBreak":
            return "\n"
        case "mention":
            let label = node["attrs"]?["label"]?.stringValue ?? node["attrs"]?["id"]?.stringValue ?? ""
            return label.isEmpty ? "" : "@\(label)"
        case "bulletList", "orderedList", "blockquote":
            return (node["content"]?.arrayValue ?? []).map(inlineText).joined(separator: "\n")
        default:
            return (node["content"]?.arrayValue ?? []).map(inlineText).joined()
        }
    }

    /// The outgoing document for typed text (03 §11): one paragraph, lines joined with hard
    /// breaks, never interpreted as markup. `nil` when the text is blank.
    public static func outgoingDocument(for rawText: String) -> (text: String, doc: JSONValue)? {
        let text = rawText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmed
        guard !text.isEmpty else { return nil }
        var content: [JSONValue] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if index > 0 { content.append(.object(["type": "hardBreak"])) }
            if !line.isEmpty { content.append(.object(["type": "text", "text": .string(line)])) }
        }
        let paragraph = JSONValue.object(["type": "paragraph", "content": .array(content)])
        return (text, .object(["type": "doc", "content": .array([paragraph])]))
    }
}
