import Foundation
import WaiveraData

/// One reaction pill: the emoji, how many people used it and whether I did.
struct ReactionSummary: Hashable, Sendable, Identifiable {
    var emoji: String
    var count: Int
    var mine: Bool
    var userIds: [String]

    var id: String { emoji }
    /// The count shows only when more than one person reacted (03 §13).
    var showsCount: Bool { count > 1 }
}

/// Who reacted, as the details sheet names them (03 §13); the view localizes each case.
enum ReactorName: Hashable, Sendable {
    case you
    case name(String)
    case userId(String)
    case unknown
}

enum ReactionRules {
    /// The fixed set offered anywhere in the app (03 §13).
    static let quick = Reaction.palette

    /// Grouped by trimmed emoji in first-seen order.
    static func summarize(_ reactions: [Reaction], viewerId: String?) -> [ReactionSummary] {
        var order: [String] = []
        var users: [String: [String]] = [:]
        for reaction in reactions {
            let emoji = reaction.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !emoji.isEmpty else { continue }
            if users[emoji] == nil { order.append(emoji) }
            users[emoji, default: []].append(reaction.userId)
        }
        return order.map { emoji in
            let ids = users[emoji] ?? []
            return ReactionSummary(
                emoji: emoji,
                count: ids.count,
                mine: viewerId.map { ids.contains($0) } ?? false,
                userIds: ids
            )
        }
    }

    /// `You` for the viewer, else the reaction's own name, else a known name, else the id.
    static func reactorName(
        _ reaction: Reaction,
        viewerId: String?,
        names: [String: String]
    ) -> ReactorName {
        let id = reaction.userId.trimmingCharacters(in: .whitespaces)
        if let viewerId, id == viewerId { return .you }
        if let name = reaction.fullName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return .name(name)
        }
        if let name = names[id], !name.isEmpty { return .name(name) }
        return id.isEmpty ? .unknown : .userId(id)
    }

    /// The reactions for one emoji, in arrival order, for the details sheet's list.
    static func reactions(_ reactions: [Reaction], emoji: String) -> [Reaction] {
        reactions.filter { $0.emoji.trimmingCharacters(in: .whitespacesAndNewlines) == emoji }
    }

    /// The tab the details sheet opens on: the long-pressed emoji if it is still there.
    static func initialTab(requested: String, in summaries: [ReactionSummary]) -> String? {
        summaries.contains { $0.emoji == requested } ? requested : summaries.first?.emoji
    }
}
