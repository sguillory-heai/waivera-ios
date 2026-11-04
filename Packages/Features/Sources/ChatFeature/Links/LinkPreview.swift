import Foundation
import WaiveraAPI
import WaiveraData

enum LinkKind: Hashable, Sendable {
    case task, resource, faq
}

/// What a Waivera link in a message points at. Equal targets share one preview.
enum LinkTarget: Hashable, Sendable {
    /// `/task/HEA-1042` or `/task/1042`; `prefix` is the agency's, when the link names it.
    case task(number: Int, prefix: String?)
    /// `/faqs/article/{id}` (`id`, lower case) or `/faqs/{slug}`.
    case faq(id: String?, slug: String?)
    /// `/resources/{id}`, the id in lower case.
    case resource(id: String)

    var kind: LinkKind {
        switch self {
        case .task: .task
        case .faq: .faq
        case .resource: .resource
        }
    }
}

/// A Waivera link in a message, resolved for the person reading it. Titles and details are one line.
enum LinkPreview: Hashable, Sendable {
    case loading(LinkKind)
    /// The person can't see it, or it no longer exists; the server doesn't say which.
    case unavailable(LinkKind)
    /// `due` is a literal calendar date; `dueLabel` is it as shown ("Nov 12", with the year
    /// when it falls in another year than today), formatted once when the preview lands.
    case task(id: Int, key: String, title: String, state: TaskState, due: CalendarDate?, dueLabel: String?)
    case resource(title: String, provider: String?, place: String?)
    case faq(title: String, summary: String?)

    var kind: LinkKind {
        switch self {
        case .loading(let kind), .unavailable(let kind): kind
        case .task: .task
        case .resource: .resource
        case .faq: .faq
        }
    }

    /// What the link is called in the text once it resolves; nil while loading or unavailable.
    var shortName: String? {
        switch self {
        case .task(_, let key, _, _, _, _): key
        case .resource(let title, _, _), .faq(let title, _): title
        case .loading, .unavailable: nil
        }
    }

    /// Tasks open in the app and resources and FAQs on the web; loading and unavailable do nothing.
    var opens: Bool { shortName != nil }
}

/// One link of a message and its preview; `href` is the link as written, which opening resolves.
struct MessageLink: Hashable, Sendable {
    var href: String
    var preview: LinkPreview
}

/// What tapping a Waivera link does.
enum LinkDestination: Equatable, Sendable {
    case task(id: Int)
    case web(URL)
}
