import Foundation
import WaiveraAPI
import WaiveraData

/// Previews for the Waivera links in one screen's messages (Android `ChatLinkResolver`). Each
/// target is read once while the screen is open, with the reader's own access, and the published
/// FAQs once for every article link; a new screen reads again, so a change of access shows the
/// next time a chat opens. Anything the reader can't open, or that fails to load, is unavailable.
@MainActor
final class ChatLinkResolver {
    let links: ChatLinks
    private(set) var previews: [LinkTarget: LinkPreview] = [:]
    /// Runs after a preview lands, so the screen can decorate its rows again.
    var onChange: (@MainActor () -> Void)?

    private let lookups: (any LinkLookupRepository)?
    private let today: @MainActor () -> CalendarDate?
    private var work: [LinkTarget: Task<Void, Never>] = [:]
    private var faqIndex: Task<[LinkedFaq]?, Never>?

    init(
        lookups: (any LinkLookupRepository)?,
        webBase: URL?,
        today: @escaping @MainActor () -> CalendarDate?
    ) {
        self.lookups = lookups
        self.today = today
        links = ChatLinks(webBase: webBase)
    }

    /// Rows with their links' previews attached and their text presented, plus every target
    /// they name, in order.
    func decorate(_ items: [TimelineItem]) -> (items: [TimelineItem], wanted: [LinkTarget]) {
        var wanted: [LinkTarget] = []
        let decorated = items.map { item -> TimelineItem in
            guard case .message(let row) = item else { return item }
            return .message(decorate(row, wanted: &wanted))
        }
        return (decorated, wanted)
    }

    func decorate(_ row: MessageRow, wanted: inout [LinkTarget]) -> MessageRow {
        guard let rich = row.rich, !row.message.isDeleted else { return row }
        let found = links.targets(rich)
        guard !found.isEmpty else { return row }
        wanted.append(contentsOf: found.map(\.target))
        var row = row
        row.rich = links.present(rich, previews: previews)
        row.links = found.map { MessageLink(href: $0.href, preview: previews[$0.target] ?? .loading($0.target.kind)) }
        return row
    }

    /// Starts reading every target not read yet.
    func request(_ targets: [LinkTarget]) {
        let fresh = targets.filter { previews[$0] == nil }
        guard !fresh.isEmpty else { return }
        for target in fresh where previews[target] == nil {
            previews[target] = .loading(target.kind)
            work[target] = Task { [weak self] in
                guard let preview = await self?.resolve(target) else { return }
                guard !Task.isCancelled else { return }
                self?.landed(target, preview)
            }
        }
    }

    /// What opening `href` does: a task opens in the app once its preview knows it, the rest on
    /// the web app. Nil for a link that is neither.
    func destination(for href: String) -> LinkDestination? {
        if let target = links.target(href), case .task(let id, _, _, _, _, _) = previews[target] {
            return .task(id: id)
        }
        guard let url = links.absolute(href), SafeLinks.isAllowed(url) else { return nil }
        return .web(url)
    }

    /// The screen closed: lookups still running stop, and their links read again next time.
    func stop() {
        for (target, task) in work {
            task.cancel()
            if case .loading = previews[target] { previews[target] = nil }
        }
        work.removeAll()
        faqIndex?.cancel()
        faqIndex = nil
    }

    private func landed(_ target: LinkTarget, _ preview: LinkPreview) {
        work[target] = nil
        previews[target] = preview
        onChange?()
    }

    private func resolve(_ target: LinkTarget) async -> LinkPreview {
        let preview: LinkPreview?
        switch target {
        case .task(let number, let prefix): preview = await task(number: number, prefix: prefix)
        case .resource(let id): preview = await resource(id: id)
        case .faq(let id, let slug): preview = await faq(id: id, slug: slug)
        }
        return preview ?? .unavailable(target.kind)
    }

    /// The server reads the number in the reader's agency; a link naming another agency's prefix
    /// points at someone else's task that happens to share the number.
    private func task(number: Int, prefix: String?) async -> LinkPreview? {
        guard let lookups, let task = try? await lookups.task(number: number) else { return nil }
        let parts = task.key.split(separator: "-", omittingEmptySubsequences: false)
        let keyPrefix = parts.count > 1 ? String(parts[0]) : nil
        let keyNumber = parts.last.map(String.init) ?? ""
        guard keyNumber == String(number) else { return nil }
        if let prefix, keyPrefix?.caseInsensitiveCompare(prefix) != .orderedSame { return nil }
        return .task(
            id: task.id,
            key: task.key,
            title: task.title,
            state: task.state,
            due: task.due,
            dueShowsYear: task.due.map { $0.year != today()?.year } ?? false
        )
    }

    private func resource(id: String) async -> LinkPreview? {
        guard let lookups, let resource = try? await lookups.resource(id: id) else { return nil }
        return .resource(title: resource.title, provider: resource.provider, place: resource.city)
    }

    private func faq(id: String?, slug: String?) async -> LinkPreview? {
        guard let lookups else { return nil }
        let index =
            faqIndex
            ?? Task { try? await lookups.faqs() }
        faqIndex = index
        guard let articles = await index.value,
            let article = articles.first(where: { id != nil ? $0.id == id : $0.slug == slug })
        else { return nil }
        return .faq(title: article.title, summary: article.summary)
    }
}
