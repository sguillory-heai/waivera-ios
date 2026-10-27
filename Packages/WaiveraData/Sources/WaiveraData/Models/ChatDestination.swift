import Foundation

/// Where a tap on an activity row, bookmark, banner or push opens (06 §A3, §B2, 09 §7).
public enum ChatDestination: Sendable, Hashable, Codable {
    case conversation(id: Int, targetMessageId: Int?)
    case thread(rootMessageId: Int, conversationId: Int, targetMessageId: Int?)

    /// Threads open at the root, never the direct parent, so nested replies resolve.
    public init(message: ChatMessage) {
        if let root = message.threadRootId {
            self = .thread(rootMessageId: root, conversationId: message.conversationId, targetMessageId: message.id)
        } else {
            self = .conversation(id: message.conversationId, targetMessageId: message.id)
        }
    }

    public var conversationId: Int {
        switch self {
        case .conversation(let id, _): id
        case .thread(_, let conversationId, _): conversationId
        }
    }
}
