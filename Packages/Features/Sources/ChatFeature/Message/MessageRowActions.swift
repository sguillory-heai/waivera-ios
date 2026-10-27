#if canImport(UIKit)
    import Foundation
    import WaiveraData

    /// Everything a row can ask for. A `nil` callback turns that affordance off (read-only rows,
    /// thread chips inside a thread).
    struct MessageRowActions {
        var toggleTimestamp: @MainActor (_ key: String) -> Void = { _ in }
        var longPress: (@MainActor (ChatMessage) -> Void)?
        var react: (@MainActor (_ messageId: Int, _ emoji: String) -> Void)?
        var reactionDetails: (@MainActor (_ messageId: Int, _ emoji: String) -> Void)?
        var openThread: (@MainActor (ChatMessage) -> Void)?
        var openAttachment: @MainActor (ChatMessage) -> Void = { _ in }
        var openPerson: @MainActor (_ userId: String) -> Void = { _ in }
        var retry: @MainActor (_ clientMessageId: String) -> Void = { _ in }
        var editFailed: (@MainActor (OutgoingMessage) -> Void)?
        var discard: @MainActor (_ clientMessageId: String) -> Void = { _ in }
        var openTicket: @MainActor (URL) -> Void = { _ in }
        var loadImage: @MainActor (_ messageId: Int) async throws -> Data = { _ in
            throw CancellationError()
        }
        var loadAvatar: @MainActor (_ userId: String) async -> Data? = { _ in nil }
    }

    /// What every row needs to know about the list: time, names and transient row state.
    struct RowContext {
        var now: Date
        var zone: TimeZone
        var names: [String: String]
        var visibleTimestamps: Set<String>
        var highlightKey: String?

        func authorName(_ message: ChatMessage) -> String {
            ChatNames.authorName(message, names: names) ?? ConversationStrings.text("unknown.author")
        }
    }
#endif
