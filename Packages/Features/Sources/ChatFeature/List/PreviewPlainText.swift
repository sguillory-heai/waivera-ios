import Foundation
import WaiveraAPI
import WaiveraData

/// Plain text for an inbox preview when a message body is a serialized TipTap document (rich
/// text sent from the web editor) or simple HTML instead of text. The document walk is
/// `RichText.plainText`; this only finds the document, which may sit under a wrapper key or be
/// encoded twice (11-pitfalls #35). Anything unrecognised is returned unchanged.
enum PreviewPlainText {
    private static let maxDepth = 8

    static func plainText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.contains("\"type\""), let text = documentText(trimmed) {
            return text
        }
        if trimmed.hasPrefix("<"), trimmed.contains(">") {
            return stripHTML(trimmed)
        }
        return raw
    }

    private static func documentText(_ json: String) -> String? {
        guard let data = json.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return findDocument(value, depth: 0).flatMap(RichText.plainText)
    }

    private static func findDocument(_ value: JSONValue, depth: Int) -> JSONValue? {
        guard depth <= maxDepth else { return nil }
        switch value {
        case .object(let fields):
            if fields["type"]?.stringValue == "doc" { return value }
            for key in fields.keys.sorted() {
                if let child = fields[key], let found = findDocument(child, depth: depth + 1) { return found }
            }
            return nil
        case .array(let items):
            for item in items {
                if let found = findDocument(item, depth: depth + 1) { return found }
            }
            return nil
        case .string(let raw):
            let inner = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard inner.hasPrefix("{"), inner.contains("\"doc\""), let data = inner.data(using: .utf8),
                let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return nil }
            return findDocument(decoded, depth: depth + 1)
        default:
            return nil
        }
    }

    private static let entities = [
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&"),
    ]

    private static func stripHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "(?i)</?(p|div|br|li|h[1-6]|blockquote)\\b[^>]*>",
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
    }
}

/// Strips the `{[TIMESTAMP- 08/10/2026 02:20:12]}` token from system text (03 §16).
enum SystemText {
    static func clean(_ value: String) -> String {
        let withoutToken = value.replacingOccurrences(
            of:
                "\\s*-?\\s*\\{\\[\\s*TIMESTAMP\\s*[-·:]\\s*\\d{1,2}/\\d{1,2}/\\d{4}\\s+\\d{1,2}:\\d{2}:\\d{2}\\s*\\]\\}\\s*",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let withoutDash = withoutToken.replacingOccurrences(of: "\\s*-\\s*$", with: "", options: .regularExpression)
        return withoutDash.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
