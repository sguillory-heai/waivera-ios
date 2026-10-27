import Foundation
import WaiveraAPI

/// A message the user sent that the server has not confirmed yet (03 §11).
public struct OutgoingMessage: Codable, Sendable, Hashable, Identifiable {
    public enum State: Codable, Sendable, Hashable {
        case sending
        /// Waiting for the network or the next automatic retry.
        case queued(attempt: Int)
        /// Shown with Retry and Discard.
        case failed(WaiveraError)
    }

    /// Client-generated UUID; the idempotency key on both send paths (rest.md, hub.md).
    public var clientMessageId: String
    public var conversationId: Int
    /// Thread root for replies.
    public var parentMessageId: Int?
    public var text: String
    public var doc: JSONValue?
    public var attachment: Attachment?
    public var createdAt: Date
    public var state: State
    public var attempts: Int

    public var id: String { clientMessageId }

    public init(
        clientMessageId: String,
        conversationId: Int,
        parentMessageId: Int?,
        text: String,
        doc: JSONValue?,
        attachment: Attachment? = nil,
        createdAt: Date,
        state: State = .sending,
        attempts: Int = 0
    ) {
        self.clientMessageId = clientMessageId
        self.conversationId = conversationId
        self.parentMessageId = parentMessageId
        self.text = text
        self.doc = doc
        self.attachment = attachment
        self.createdAt = createdAt
        self.state = state
        self.attempts = attempts
    }

    public var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}

/// A conversation's messages, oldest first, plus unconfirmed sends.
public struct MessageTimeline: Sendable, Hashable {
    public var conversationId: Int
    public var messages: [ChatMessage]
    public var pending: [OutgoingMessage]
    public var hasOlder: Bool
    public var isLoadingOlder: Bool

    public init(
        conversationId: Int,
        messages: [ChatMessage] = [],
        pending: [OutgoingMessage] = [],
        hasOlder: Bool = false,
        isLoadingOlder: Bool = false
    ) {
        self.conversationId = conversationId
        self.messages = messages
        self.pending = pending
        self.hasOlder = hasOlder
        self.isLoadingOlder = isLoadingOlder
    }

    public var isEmpty: Bool { messages.isEmpty && pending.isEmpty }

    /// The newest root message, for read-through (03 §12).
    public var newestRootMessageId: Int? { messages.last(where: { !$0.isThreadReply })?.id }
}

/// A thread: the root message plus its replies, oldest first.
public struct ThreadTimeline: Sendable, Hashable {
    public var rootMessageId: Int
    public var conversationId: Int
    public var root: ChatMessage?
    public var replies: [ChatMessage]
    public var pending: [OutgoingMessage]

    public init(
        rootMessageId: Int,
        conversationId: Int,
        root: ChatMessage? = nil,
        replies: [ChatMessage] = [],
        pending: [OutgoingMessage] = []
    ) {
        self.rootMessageId = rootMessageId
        self.conversationId = conversationId
        self.root = root
        self.replies = replies
        self.pending = pending
    }

    public var newestReplyId: Int? { replies.last?.id ?? root?.id }
}
