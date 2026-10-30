import Foundation
import WaiveraData

/// Activity feed rules from 06 §A, with the Expo bugs fixed.
enum ActivityRules {
    /// The API's page size; has-more means a full page came back.
    static let pageSize = 30

    /// One row per id across every loaded page, the later copy winning, newest first by parsed
    /// UTC instant (zone-less values were already read as UTC by the shared parser), then by id.
    static func merge(_ items: [ActivityItem]) -> [ActivityItem] {
        var byId: [Int64: ActivityItem] = [:]
        for item in items { byId[item.id] = item }
        return byId.values.sorted(by: newestFirst)
    }

    static func newestFirst(_ lhs: ActivityItem, _ rhs: ActivityItem) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case (let left?, let right?) where left != right: left > right
        case (.some, nil): true
        case (nil, .some): false
        default: lhs.id > rhs.id
        }
    }

    static func summary(_ item: ActivityItem) -> ActivitySummary {
        if item.kind == .reaction {
            return .reaction(actor: item.actorDisplayName?.trimmedNonEmpty, emoji: item.reactionType?.trimmedNonEmpty)
        }
        if let text = item.summary?.trimmedNonEmpty { return .server(text) }
        return .fallback
    }

    /// AND of the type chip and the Unread toggle. Unknown types appear only under All.
    static func matches(kind: ActivityItem.Kind, isRead: Bool, filter: ActivityFilter, unreadOnly: Bool) -> Bool {
        if unreadOnly && isRead { return false }
        switch filter {
        case .all: return true
        case .mentions: return kind == .mention
        case .replies: return kind == .threadReply
        case .reactions: return kind == .reaction
        }
    }

    /// Case-insensitive substring match against the text the row shows or the actor's name.
    static func matches(query: String, summaryText: String, actor: String?) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return summaryText.localizedCaseInsensitiveContains(needle)
            || (actor?.localizedCaseInsensitiveContains(needle) ?? false)
    }

    /// The API has no unread total, so the badge can only count loaded pages. When the oldest
    /// loaded page still holds unread items and more pages exist, older pages probably hold more:
    /// the screen loads them (up to a cap) and, past the cap, shows the count as a lower bound.
    static func olderPagesMayHoldUnread(
        _ merged: [ActivityItem],
        hasMore: Bool,
        isRead: (ActivityItem) -> Bool
    ) -> Bool {
        hasMore && merged.suffix(pageSize).contains { !isRead($0) }
    }
}

extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
