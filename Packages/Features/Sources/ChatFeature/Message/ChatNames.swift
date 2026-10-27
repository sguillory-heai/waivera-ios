import Foundation
import WaiveraData

/// Display names by backend user id, for rows, reactions and typing.
enum ChatNames {
    /// Directory first, then the conversation's participants, then message authors, so the
    /// most specific source wins.
    static func names(
        directory: [DirectoryPerson],
        participants: [ChatUser],
        messages: [ChatMessage]
    ) -> [String: String] {
        var names: [String: String] = [:]
        for person in directory where !person.name.trimmingCharacters(in: .whitespaces).isEmpty {
            names[person.id] = person.name
        }
        for user in participants {
            if let name = user.fullName { names[user.id] = name }
        }
        for message in messages {
            if let author = message.author, let name = author.fullName { names[author.id] = name }
        }
        return names
    }

    /// The message's own author name, else a known name; `nil` means "Unknown user".
    static func authorName(_ message: ChatMessage, names: [String: String]) -> String? {
        if let name = message.author?.fullName { return name }
        guard let id = message.authorId ?? message.author?.id else { return nil }
        return names[id]
    }
}

/// "Priya is typing…", "Priya and Sam are typing…", "Several people are typing…". A `nil`
/// name is someone the directory does not know yet.
enum TypingLabel: Hashable, Sendable {
    case one(String?)
    case two(String?, String?)
    case many

    init?(userIds: [String], names: [String: String]) {
        let sorted = userIds.sorted()
        switch sorted.count {
        case 0: return nil
        case 1: self = .one(names[sorted[0]])
        case 2: self = .two(names[sorted[0]], names[sorted[1]])
        default: self = .many
        }
    }
}
