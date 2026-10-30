import Foundation

/// Link policy for everything that came from a message or a payload (03 §7, 11 §15): only http
/// and https with a host open, in Safari. `javascript:`, `file:`, `intent:` and custom schemes
/// are never opened.
enum SafeLinks {
    static func url(_ href: String?) -> URL? {
        guard let value = href?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
            let url = URL(string: value), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host, !host.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return url
    }

    static func isAllowed(_ url: URL?) -> Bool { url.map { self.url($0.absoluteString) != nil } ?? false }
}

/// The marks on a run of rich text. Platform-neutral, so every rule is tested on Linux; the
/// SwiftUI layer turns them into fonts and decorations (`RichTextStyler`).
enum RichMarksAttribute: AttributedStringKey {
    typealias Value = Set<RichMark>
    static let name = "waivera.richMarks"
}

/// A mention chip: the run's value is the label without the `@`.
enum RichMentionAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "waivera.mention"
}

/// Inline content (paragraph, heading) as an `AttributedString` (03 §7 marks table): marks
/// compose, a safe link keeps its marks and adds `link` (the view colours it with the accent),
/// mentions read `@label`, hard breaks are newlines.
enum RichTextAttributes {
    /// U+2011, a hyphen that never breaks a line.
    static let nonBreakingHyphen: Character = "\u{2011}"

    /// A mention's label with non-breaking hyphens, so "@Maria-Fernanda" never splits over two
    /// lines (wave 28 M2). Speech and copy use the message's plain text, which keeps "-".
    static func mentionRun(_ label: String) -> String {
        String(label.map { $0 == "-" ? nonBreakingHyphen : $0 })
    }

    static func attributed(_ inlines: [RichInline]) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .text(let text, let marks, let href):
                var container = AttributeContainer()
                if !marks.isEmpty { container[RichMarksAttribute.self] = marks }
                if let href { container[AttributeScopes.FoundationAttributes.LinkAttribute.self] = href }
                result += AttributedString(text, attributes: container)
            case .mention(let label):
                var container = AttributeContainer()
                container[RichMentionAttribute.self] = label
                result += AttributedString("@" + mentionRun(label), attributes: container)
            case .hardBreak:
                result += AttributedString("\n")
            }
        }
        return result
    }
}
