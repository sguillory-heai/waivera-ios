import Foundation
import WaiveraAPI
import WaiveraData

/// The "Not sent" banner copy (03 §11), chosen from typed errors instead of message sniffing.
enum SendErrorKind: Hashable, Sendable {
    case archived, readOnly, offline, session, server

    init(_ error: WaiveraError) {
        switch error {
        case .channelArchived: self = .archived
        case .channelReadOnly, .forbidden: self = .readOnly
        case .offline, .realtimeUnavailable: self = .offline
        case .unauthorized, .signedOut, .auth(.sessionExpired): self = .session
        default: self = .server
        }
    }
}

/// The thread screen says "reply" where the conversation says "message" (04 §3).
enum SendNoun: Hashable, Sendable {
    case message, reply
}

/// Why the composer is replaced by the lock notice (03 §18, 04 §7).
enum ReadOnlyReason: Hashable, Sendable {
    case automated
    case readOnlyChannel
    case archivedChannel
    /// The thread copy for a conversation the viewer cannot write to.
    case readOnlyThread

    static func conversation(_ conversation: Conversation) -> ReadOnlyReason? {
        if conversation.kind == .bot { return .automated }
        if conversation.isArchived || conversation.channel?.isArchived == true { return .archivedChannel }
        if !conversation.canWrite { return .readOnlyChannel }
        return nil
    }

    /// Threads keep the automated copy and use their own wording for everything else (04 §7).
    static func thread(_ conversation: Conversation) -> ReadOnlyReason? {
        guard let reason = self.conversation(conversation) else { return nil }
        return reason == .automated ? .automated : .readOnlyThread
    }
}

/// Whether the viewer may post: bots never, channels only when writable and not archived.
enum WritePermission {
    static func canWrite(_ conversation: Conversation) -> Bool {
        conversation.kind != .bot && conversation.canWrite
    }
}

/// The hub connection as a chat screen shows it in its header (05 §2). The app shell owns the
/// connection banner with Retry, so the screen does not draw a second one.
enum ConnectionSubtitle: Hashable, Sendable {
    case connecting, reconnecting, offline

    init?(_ banner: ConnectionBanner) {
        switch banner {
        case .hidden: return nil
        case .connecting: self = .connecting
        case .reconnecting: self = .reconnecting
        case .offline: self = .offline
        }
    }
}
