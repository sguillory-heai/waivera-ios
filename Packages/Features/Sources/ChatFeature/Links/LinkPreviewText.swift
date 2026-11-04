import Foundation
import WaiveraAPI
import WaiveraData

/// The words of a link preview (Android `LinkSection`), platform-neutral so they are tested on Linux.
enum LinkPreviewText {
    enum Tone: Equatable, Sendable { case accent, neutral, success, warning }

    static func kind(_ kind: LinkKind) -> String {
        switch kind {
        case .task: ConversationStrings.text("link.task")
        case .resource: ConversationStrings.text("link.resource")
        case .faq: ConversationStrings.text("link.faq")
        }
    }

    /// The quiet line above the title: "Task · HEA-1042" once a task resolves, else the kind.
    static func kicker(_ preview: LinkPreview) -> String {
        if case .task(_, let key, _, _, _, _) = preview { return ConversationStrings.format("link.task.key", key) }
        return kind(preview.kind)
    }

    static func title(_ preview: LinkPreview) -> String? {
        switch preview {
        case .task(_, _, let title, _, _, _), .resource(let title, _, _), .faq(let title, _): title
        case .loading, .unavailable: nil
        }
    }

    /// The one line under the title; a task's state shows as a badge beside its due date.
    static func meta(_ preview: LinkPreview) -> String? {
        switch preview {
        case .unavailable: return ConversationStrings.text("link.unavailable.short")
        case .task(_, _, _, _, let due, let showsYear):
            return due.map { ConversationStrings.format("link.due", dueLabel($0, showsYear: showsYear)) }
        case .resource(_, let provider, let place):
            let parts = [provider, place].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .faq(_, let summary): return summary
        case .loading: return nil
        }
    }

    static func state(_ state: TaskState) -> String {
        switch state {
        case .notStarted: ConversationStrings.text("link.state.not.started")
        case .inProgress: ConversationStrings.text("link.state.in.progress")
        case .inReview: ConversationStrings.text("link.state.in.review")
        case .completed: ConversationStrings.text("link.state.completed")
        case .closed: ConversationStrings.text("link.state.closed")
        case .other(let name): name.lowercased().prefix(1).uppercased() + name.lowercased().dropFirst()
        }
    }

    /// The Tasks tab's colours for the same states.
    static func tone(_ state: TaskState) -> Tone {
        switch state {
        case .completed, .closed: .success
        case .inProgress: .accent
        case .inReview: .warning
        case .notStarted, .other: .neutral
        }
    }

    /// "Nov 12", or "Nov 12, 2027" outside this year. A literal calendar date, so it is formatted
    /// in UTC and never shifts with a zone.
    static func dueLabel(_ day: CalendarDate, showsYear: Bool, locale: Locale = .current) -> String {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utc
        formatter.setLocalizedDateFormatFromTemplate(showsYear ? "MMMdyyyy" : "MMMd")
        return formatter.string(from: day.startInstant(in: utc))
    }

    /// What VoiceOver reads for one preview, and what opening it does.
    static func accessibilityLabel(_ preview: LinkPreview) -> String {
        switch preview {
        case .loading: return ConversationStrings.text("link.loading")
        case .unavailable: return kind(preview.kind) + ", " + ConversationStrings.text("link.unavailable")
        case .task(_, _, _, let state, _, _):
            return [kicker(preview), title(preview), self.state(state), meta(preview)].compactMap { $0 }
                .joined(separator: ", ")
        case .resource, .faq:
            return [kicker(preview), title(preview), meta(preview)].compactMap { $0 }.joined(separator: ", ")
        }
    }

    static func accessibilityHint(_ preview: LinkPreview) -> String? {
        guard preview.opens else { return nil }
        return ConversationStrings.text(preview.kind == .task ? "link.open.task" : "link.open.web")
    }
}
