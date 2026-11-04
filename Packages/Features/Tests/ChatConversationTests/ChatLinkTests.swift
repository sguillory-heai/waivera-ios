import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ChatFeature

/// Waivera links in messages (Android `ChatLinksTest` and `ChatLinkResolverTest`).
@Suite("Chat links")
@MainActor
struct ChatLinkTests {
    private let base = URL(string: "https://app.waivera.test")
    private var links: ChatLinks { ChatLinks(webBase: base) }

    private func link(_ text: String, _ href: String) -> RichInline {
        .text(text, href: URL(string: href))
    }

    private func row(_ inlines: [RichInline], id: Int = 1) -> MessageRow {
        MessageRow(
            key: "m\(id)",
            message: Fixture.message(id),
            isMine: false,
            isBot: false,
            groupedWithPrevious: false,
            groupedWithNext: false,
            rich: RichDocument(blocks: [.paragraph(inlines)]),
            ticket: nil,
            reactions: []
        )
    }

    private func resolver(_ lookups: FakeLinkLookupRepository? = nil) -> ChatLinkResolver {
        ChatLinkResolver(
            lookups: lookups ?? FakeLinkLookupRepository(tasks: FakeTasksRepository()),
            webBase: base
        ) { DemoData.today }
    }

    // MARK: Reading links

    @Test func taskLinksReadRelativeAndAbsolute() {
        #expect(links.target("/task/HEA-1042") == .task(number: 1042, prefix: "HEA"))
        #expect(links.target("/task/1042/") == .task(number: 1042, prefix: nil))
        #expect(links.target("https://app.waivera.test/task/hea-7") == .task(number: 7, prefix: "hea"))
        #expect(links.target("/task/HEA-0") == nil)
        #expect(links.target("/task/HEA-1-2") == nil)
        #expect(links.target("/task/HEA-1042/files") == nil)
    }

    @Test func onlyTheWebAppsOwnLinksCount() {
        #expect(links.target("https://evil.test/task/HEA-1042") == nil)
        #expect(links.target("http://app.waivera.test/task/HEA-1042") == nil)
        #expect(links.target("https://user:pw@app.waivera.test/task/HEA-1042") == nil)
        #expect(links.target("//app.waivera.test/task/HEA-1042") == nil)
        #expect(links.target("/task/HEA-1042\u{202E}") == nil)
        #expect(links.target("/task/HEA\\1042") == nil)
        #expect(ChatLinks(webBase: nil).target("/task/HEA-1042") == nil)
    }

    @Test func faqAndResourceLinks() {
        let id = FakeLinkLookupRepository.faqId
        #expect(links.target("/faqs/article/\(id.uppercased())") == .faq(id: id, slug: nil))
        #expect(links.target("/faqs/time-off") == .faq(id: nil, slug: "time-off"))
        #expect(links.target("/faqs/-bad") == nil)
        let resource = FakeLinkLookupRepository.resourceId
        #expect(links.target("/resources/\(resource)") == .resource(id: resource))
        #expect(links.target("/resources/\(resource)?tab=map") == nil)
        #expect(links.target("/Resources/\(resource)") == nil)
        #expect(links.target("/resources/00000000-0000-0000-0000-000000000000") == nil)
    }

    @Test func siteRelativeLinksAreKeptByTheParser() {
        #expect(ChatLinks.siteRelative("/task/HEA-1042")?.absoluteString == "/task/HEA-1042")
        #expect(ChatLinks.siteRelative("//evil.test/x") == nil)
        #expect(ChatLinks.siteRelative("task/1") == nil)
    }

    // MARK: Presenting

    @Test func resolvedAddressesTakeTheShortNameWhereverTheySit() {
        let target = LinkTarget.task(number: 1042, prefix: "HEA")
        let preview = LinkPreview.task(
            id: 12,
            key: "HEA-1042",
            title: "Intake review",
            state: .inProgress,
            due: nil,
            dueLabel: nil
        )
        let middle = RichDocument(blocks: [
            .paragraph([.text("See "), link("/task/HEA-1042", "/task/HEA-1042"), .text(" today")])
        ])
        #expect(
            links.present(middle, previews: [target: preview]).blocks == [
                .paragraph([.text("See "), link("HEA-1042", "/task/HEA-1042"), .text(" today")])
            ]
        )
        let trailing = RichDocument(blocks: [.paragraph([.text("See "), link("/task/HEA-1042", "/task/HEA-1042")])])
        #expect(
            links.present(trailing, previews: [target: preview]).blocks == [
                .paragraph([.text("See "), link("HEA-1042", "/task/HEA-1042")])
            ]
        )
        let onlyLink = RichDocument(blocks: [.paragraph([link("/task/HEA-1042", "/task/HEA-1042")])])
        #expect(
            links.present(onlyLink, previews: [target: preview]).blocks == [
                .paragraph([link("HEA-1042", "/task/HEA-1042")])
            ]
        )
        #expect(links.present(trailing, previews: [target: .loading(.task)]) == trailing)
    }

    @Test func atMostTwentyDistinctTargets() {
        let inlines = (1...25).map { link("t\($0)", "/task/\($0)") } + [link("again", "/task/1")]
        let found = links.targets(RichDocument(blocks: [.paragraph(inlines)]))
        #expect(found.count == ChatLinks.maxLinks)
        #expect(found.first?.target == .task(number: 1, prefix: nil))
    }

    // MARK: Resolving

    @Test func taskResolvesThenOpensInTheApp() async {
        let resolver = resolver()
        var wanted: [LinkTarget] = []
        let first = resolver.decorate(row([.text("See "), link("/task/HEA-1042", "/task/HEA-1042")]), wanted: &wanted)
        #expect(first.links.map(\.preview) == [.loading(.task)])
        #expect(
            resolver.destination(for: "/task/HEA-1042")
                == base.flatMap { URL(string: "/task/HEA-1042", relativeTo: $0)?.absoluteURL }.map(LinkDestination.web)
        )
        var changes = 0
        resolver.onChange = { changes += 1 }
        resolver.request(wanted)
        #expect(await eventually { changes == 1 })
        var again: [LinkTarget] = []
        let decorated = resolver.decorate(
            row([.text("See "), link("/task/HEA-1042", "/task/HEA-1042")]),
            wanted: &again
        )
        guard case .task(let id, let key, let title, let state, let due, let label) = decorated.links.first?.preview
        else {
            Issue.record("task did not resolve")
            return
        }
        #expect(id == 12 && key == "HEA-1042" && title == "Intake review" && state == .inProgress)
        // Due this year, so its label leaves the year out.
        #expect(due.map { LinkPreviewText.dueLabel($0, showsYear: false) } == label)
        #expect(decorated.rich?.blocks == [.paragraph([.text("See ")])])
        #expect(resolver.destination(for: "/task/HEA-1042") == .task(id: 12))
    }

    @Test func anotherAgencysPrefixIsUnavailable() async {
        let resolver = resolver()
        resolver.request([.task(number: 1042, prefix: "OTH")])
        #expect(await eventually { resolver.previews[.task(number: 1042, prefix: "OTH")] == .unavailable(.task) })
        #expect(resolver.destination(for: "/task/OTH-1042")?.isTask == false)
    }

    @Test func resourcesAndFaqsResolveAndShareOneFaqRead() async {
        let lookups = FakeLinkLookupRepository(tasks: FakeTasksRepository())
        let resolver = resolver(lookups)
        let resource = LinkTarget.resource(id: FakeLinkLookupRepository.resourceId)
        let byId = LinkTarget.faq(id: FakeLinkLookupRepository.faqId, slug: nil)
        let bySlug = LinkTarget.faq(id: nil, slug: "mileage")
        let missing = LinkTarget.faq(id: nil, slug: "nope")
        resolver.request([resource, byId, bySlug, missing])
        #expect(
            await eventually {
                [resource, byId, bySlug, missing].allSatisfy { resolver.previews[$0]?.isSettled == true }
            }
        )
        #expect(
            resolver.previews[resource]
                == .resource(title: "North County Respite", provider: "Family Care Network", place: "Austin")
        )
        #expect(resolver.previews[bySlug] == .faq(title: "Logging mileage", summary: nil))
        #expect(resolver.previews[missing] == .unavailable(.faq))
        #expect(lookups.calls.all.filter { $0 == "faqs" }.count == 1)
        guard case .web(let url) = resolver.destination(for: "/faqs/mileage") else {
            Issue.record("FAQ should open on the web")
            return
        }
        #expect(url.absoluteString == "https://app.waivera.test/faqs/mileage")
    }

    @Test func failuresAreUnavailableAndEachTargetIsReadOnce() async {
        let lookups = FakeLinkLookupRepository(tasks: FakeTasksRepository())
        lookups.failure.update { $0 = .offline }
        let resolver = resolver(lookups)
        let target = LinkTarget.task(number: 1042, prefix: nil)
        resolver.request([target, target])
        #expect(await eventually { resolver.previews[target] == .unavailable(.task) })
        resolver.request([target])
        #expect(lookups.calls.all == ["task:1042"])
    }

    @Test func deletedMessagesShowNoPreviews() {
        var message = row([link("/task/1042", "/task/1042")])
        message.message.isDeleted = true
        var wanted: [LinkTarget] = []
        #expect(resolver().decorate(message, wanted: &wanted).links.isEmpty)
        #expect(wanted.isEmpty)
    }

    // MARK: Words

    @Test func previewWords() {
        let task = LinkPreview.task(
            id: 12,
            key: "HEA-1042",
            title: "Intake review",
            state: .inReview,
            due: CalendarDate(year: 2027, month: 3, day: 14),
            dueLabel: "Mar 14, 2027"
        )
        let en = Locale(identifier: "en_US")
        #expect(LinkPreviewText.kicker(task) == "Task · HEA-1042")
        #expect(LinkPreviewText.meta(task) == "Due Mar 14, 2027")
        #expect(
            LinkPreviewText.dueLabel(
                CalendarDate(year: 2026, month: 11, day: 1) ?? DemoData.today,
                showsYear: false,
                locale: en
            ) == "Nov 1"
        )
        #expect(
            LinkPreviewText.dueLabel(
                CalendarDate(year: 2027, month: 3, day: 14) ?? DemoData.today,
                showsYear: true,
                locale: en
            ) == "Mar 14, 2027"
        )
        #expect(LinkPreviewText.state(.inReview) == "In review")
        #expect(LinkPreviewText.tone(.closed) == .success)
        #expect(LinkPreviewText.meta(.resource(title: "R", provider: "P", place: nil)) == "P")
        #expect(LinkPreviewText.meta(.unavailable(.faq)) == "Not available to you")
        #expect(LinkPreviewText.accessibilityHint(.loading(.task)) == nil)
    }

    /// Due dates are literal days: the clock change on 1 Nov 2026 and 8 Mar 2026 never moves them.
    @Test func dueDatesHoldAcrossDSTBoundaries() {
        let en = Locale(identifier: "en_US")
        for (month, day) in [(11, 1), (3, 8)] {
            guard let date = CalendarDate(year: 2026, month: month, day: day) else {
                Issue.record("bad date")
                continue
            }
            let label = LinkPreviewText.dueLabel(date, showsYear: false, locale: en)
            #expect(label == (month == 11 ? "Nov 1" : "Mar 8"))
        }
    }
}

extension LinkPreview {
    fileprivate var isSettled: Bool {
        if case .loading = self { return false }
        return true
    }
}

extension LinkDestination {
    fileprivate var isTask: Bool {
        if case .task = self { return true }
        return false
    }
}
