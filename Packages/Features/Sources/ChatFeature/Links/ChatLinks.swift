import Foundation

/// Finds Waivera links in messages and decides how they show, by the web's rules
/// (`TaskFaqLinkPreviews.tsx`, `ResourceChatService.ts`; Android `ChatLinks`): only links on the
/// configured web app, site-relative or absolute, without credentials; at most 20 per message.
struct ChatLinks: Sendable {
    static let maxLinks = 20
    static let maxHref = 2_048
    private static let nilUUID = "00000000-0000-0000-0000-000000000000"

    let webBase: URL?

    // MARK: Reading links

    /// The target `href` points at, or nil for anything that isn't a Waivera task, FAQ or resource.
    func target(_ href: String) -> LinkTarget? {
        guard href.count <= Self.maxHref, !Self.isUnsafe(href), let url = absolute(href),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let path = components.percentEncodedPath
        return task(path) ?? faq(path) ?? resource(path, components: components)
    }

    /// `href` as a full address on the web app: site-relative links resolve against the web base;
    /// absolute ones must already be on it. Nil for anything else.
    func absolute(_ href: String) -> URL? {
        guard let base = webBase, !Self.isUnsafe(href) else { return nil }
        let url: URL?
        if href.hasPrefix("/"), !href.hasPrefix("//") {
            url = URL(string: href, relativeTo: base)?.absoluteURL
        } else {
            url = URL(string: href)
        }
        guard let url, url.scheme?.lowercased() == base.scheme?.lowercased(),
            url.host?.lowercased() == base.host?.lowercased(), url.port == base.port,
            url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    private func task(_ path: String) -> LinkTarget? {
        guard let raw = Self.single(path, under: ["task"], trailingSlash: true),
            let reference = raw.removingPercentEncoding
        else { return nil }
        let parts = reference.split(separator: "-", omittingEmptySubsequences: false)
        let prefix: Substring?
        let digits: Substring
        switch parts.count {
        case 1: (prefix, digits) = (nil, parts[0])
        case 2: (prefix, digits) = (parts[0], parts[1])
        default: return nil
        }
        if let prefix, prefix.isEmpty || !prefix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return nil
        }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits),
            (1...Int(Int32.max)).contains(number)
        else { return nil }
        return .task(number: number, prefix: prefix.map(String.init))
    }

    private func faq(_ path: String) -> LinkTarget? {
        if let raw = Self.single(path, under: ["faqs", "article"], trailingSlash: true) {
            guard let id = raw.removingPercentEncoding, Self.isUUID(id) else { return nil }
            return .faq(id: id.lowercased(), slug: nil)
        }
        guard let raw = Self.single(path, under: ["faqs"], trailingSlash: true), let slug = raw.removingPercentEncoding,
            Self.isSlug(slug)
        else { return nil }
        return .faq(id: nil, slug: slug)
    }

    /// Resource links never carry a query or fragment, as the web writes them.
    private func resource(_ path: String, components: URLComponents) -> LinkTarget? {
        guard components.percentEncodedQuery == nil, components.percentEncodedFragment == nil,
            let id = Self.single(path, under: ["resources"], trailingSlash: false, caseSensitive: true),
            Self.isUUID(id), id != Self.nilUUID
        else { return nil }
        return .resource(id: id.lowercased())
    }

    /// The one segment after `prefix` in `path` ("/task/HEA-1"), or nil when the path is anything else.
    private static func single(
        _ path: String,
        under prefix: [String],
        trailingSlash: Bool,
        caseSensitive: Bool = false
    ) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var segments = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if trailingSlash, segments.count == prefix.count + 2, segments.last == "" { segments.removeLast() }
        guard segments.count == prefix.count + 1, let last = segments.last, !last.isEmpty else { return nil }
        for (segment, expected) in zip(segments, prefix) {
            let same = caseSensitive ? segment == expected : segment.lowercased() == expected
            if !same { return nil }
        }
        return last
    }

    /// Controls, bidi overrides and backslashes are refused before parsing can hide them.
    static func isUnsafe(_ href: String) -> Bool {
        href.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x00...0x20, 0x7F...0x9F, 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069, 0x5C: true
            default: false
            }
        }
    }

    static func isUUID(_ value: String) -> Bool {
        let groups = value.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.map(\.count) == [8, 4, 4, 4, 12] else { return false }
        return groups.allSatisfy { $0.allSatisfy(\.isHexDigit) && $0.allSatisfy(\.isASCII) }
    }

    static func isSlug(_ value: String) -> Bool {
        guard let first = value.first, value.count <= 200, first.isASCII, first.isLetter || first.isNumber else {
            return false
        }
        return value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// A site-relative link as the editor writes it ("/task/HEA-1042"), kept so it can preview and
    /// open on the web app; nil for anything else. Absolute links go through `SafeLinks`.
    static func siteRelative(_ href: String?) -> URL? {
        guard let value = href?.trimmingCharacters(in: .whitespacesAndNewlines), value.hasPrefix("/"),
            !value.hasPrefix("//"), value.count <= maxHref, !isUnsafe(value)
        else { return nil }
        return URL(string: value)
    }

    // MARK: Documents

    /// Each distinct target in `document`, in reading order, with the first link that named it.
    func targets(_ document: RichDocument) -> [(href: String, target: LinkTarget)] {
        var found: [(href: String, target: LinkTarget)] = []
        var seen = Set<LinkTarget>()
        RichWalk.forEachInline(document.blocks) { inline in
            guard found.count < Self.maxLinks, case .text(_, _, let href?) = inline,
                let target = target(href.absoluteString), seen.insert(target).inserted
            else { return }
            found.append((href.absoluteString, target))
        }
        return found
    }

    /// `document` as it reads once its links have previews: every address shown as text becomes
    /// the short name of what it points at (a task's number, a resource's or article's title),
    /// wherever it sits, so each preview has a name in the text to match, and a message that was
    /// only a link still reads as something. Links still loading, or that the reader can't open,
    /// stay as written.
    func present(_ document: RichDocument, previews: [LinkTarget: LinkPreview]) -> RichDocument {
        func resolved(_ href: URL?) -> LinkPreview? {
            guard let href, let target = target(href.absoluteString), let preview = previews[target],
                preview.shortName != nil
            else { return nil }
            return preview
        }
        let renamed = RichWalk.mapInlines(document.blocks) { inlines in
            inlines.map { inline in
                guard case .text(let text, let marks, let href?) = inline, let name = resolved(href)?.shortName,
                    Self.looksLikeAddress(text, href: href.absoluteString)
                else { return inline }
                return .text(name, marks: marks, href: href)
            }
        }
        return RichDocument(blocks: renamed)
    }

    private static func looksLikeAddress(_ text: String, href: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        return trimmed == href || lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
            || trimmed.hasPrefix("/")
    }
}

/// Visits and rewrites every run of inline content in a document, wherever it sits.
enum RichWalk {
    static func forEachInline(_ blocks: [RichBlock], _ visit: (RichInline) -> Void) {
        for block in blocks {
            switch block {
            case .paragraph(let inlines), .heading(_, let inlines): inlines.forEach(visit)
            case .blockquote(let children), .group(let children): forEachInline(children, visit)
            case .list(_, let items): items.forEach { forEachInline($0, visit) }
            case .table(let rows): rows.joined().forEach { forEachInline($0, visit) }
            case .codeBlock, .horizontalRule: break
            }
        }
    }

    static func mapInlines(_ blocks: [RichBlock], _ change: ([RichInline]) -> [RichInline]) -> [RichBlock] {
        blocks.map { block in
            switch block {
            case .paragraph(let inlines): .paragraph(change(inlines))
            case .heading(let level, let inlines): .heading(level: level, change(inlines))
            case .blockquote(let children): .blockquote(mapInlines(children, change))
            case .group(let children): .group(mapInlines(children, change))
            case .list(let ordered, let items): .list(ordered: ordered, items: items.map { mapInlines($0, change) })
            case .table(let rows): .table(rows: rows.map { row in row.map { mapInlines($0, change) } })
            case .codeBlock, .horizontalRule: block
            }
        }
    }
}
