import Foundation

/// A chat activity summary split for the Needs you card: the server writes a mention as
/// `{sender} mentioned you: "{snippet}"`, and the card shows the lead as the headline and the
/// snippet as a quote on its own line. `lead` is `nil` when the summary is not in that shape, and
/// then the whole summary is the `quote`.
struct QuotedSummary: Hashable, Sendable {
    var lead: String?
    var quote: String

    private static let separator = ": \""

    static func of(_ summary: String) -> QuotedSummary {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: separator), range.lowerBound > text.startIndex else {
            return QuotedSummary(lead: nil, quote: text)
        }
        let lead = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        var quote = String(text[range.upperBound...])
        if quote.hasSuffix("\"") { quote.removeLast() }
        quote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lead.isEmpty, !quote.isEmpty else { return QuotedSummary(lead: nil, quote: text) }
        return QuotedSummary(lead: lead, quote: quote)
    }
}
