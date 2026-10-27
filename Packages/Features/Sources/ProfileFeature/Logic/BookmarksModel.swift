import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// What a bookmark row says when the message has no text.
public enum BookmarkPreview: Hashable, Sendable {
    case text(String)
    /// An image-only message: more specific than "File attachment" (06 §B4).
    case photo
    case file(name: String?)
    case saved
}

public struct BookmarkRow: Identifiable, Hashable, Sendable {
    public var id: Int { messageID }
    public var messageID: Int
    public var conversationID: Int
    /// Where a thread reply opens: the thread root, never the direct parent (11-pitfalls #21).
    public var threadRootID: Int?
    public var author: String?
    public var createdAt: Date?
    public var preview: BookmarkPreview

    public var isThreadReply: Bool { threadRootID != nil }
}

/// Localised words a search can match besides the message itself ("thread reply", "photo").
public struct BookmarkSearchWords: Hashable, Sendable {
    public var threadReply: String
    public var message: String
    public var photo: String
    public var file: String

    public init(
        threadReply: String = "thread reply",
        message: String = "message",
        photo: String = "photo",
        file: String = "file"
    ) {
        self.threadReply = threadReply
        self.message = message
        self.photo = photo
        self.file = file
    }
}

/// Mapping, ordering and search rules from 06 §B, pure for tests.
public enum BookmarkRules {
    /// Rows need a positive conversation id (the stricter of the two Expo rules) and a message
    /// that still exists. Newest first: instants come from the shared UTC parser, so zone-less
    /// and zoned timestamps order together (11-pitfalls #20).
    public static func rows(_ bookmarks: [Bookmark]) -> [BookmarkRow] {
        var seen = Set<Int>()
        return bookmarks.map(\.message)
            .filter { $0.conversationId > 0 && !$0.isDeleted && seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let left = lhs.createdAt ?? .distantPast
                let right = rhs.createdAt ?? .distantPast
                return left == right ? lhs.id > rhs.id : left > right
            }
            .map(row)
    }

    public static func row(_ message: ChatMessage) -> BookmarkRow {
        let threadRoot: Int? =
            switch ChatDestination(message: message) {
            case .thread(let root, _, _): root
            case .conversation: nil
            }
        return BookmarkRow(
            messageID: message.id,
            conversationID: message.conversationId,
            threadRootID: threadRoot,
            author: message.author?.fullName,
            createdAt: message.createdAt,
            preview: preview(message)
        )
    }

    public static func preview(_ message: ChatMessage) -> BookmarkPreview {
        let text = (message.bodyText ?? "")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if !text.isEmpty { return .text(text) }
        guard let attachment = message.attachment else { return .saved }
        return attachment.kind == .image ? .photo : .file(name: attachment.name?.nonBlank)
    }

    public static func matches(_ row: BookmarkRow, query: String, words: BookmarkSearchWords) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        var haystack = [row.author ?? "", row.isThreadReply ? words.threadReply : words.message]
        switch row.preview {
        case .text(let text): haystack.append(text)
        case .photo: haystack.append(words.photo)
        case .file(let name): haystack += [words.file, name ?? ""]
        case .saved: break
        }
        return haystack.joined(separator: " ")
            .range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// Saved messages. Leaving the screen cancels `run()`, and with it a refresh in flight,
/// including the slow per-conversation fallback (gap G-04). Removing is optimistic with Undo;
/// a failure puts the row back and says so.
@MainActor
@Observable
public final class BookmarksModel {
    public enum RemoveOutcome: Equatable, Sendable {
        case removed
        case failed(WaiveraError)
        case ignored
    }

    public var query = "" {
        didSet { if query != oldValue { derive() } }
    }

    public var searchWords = BookmarkSearchWords() {
        didSet { if searchWords != oldValue { derive() } }
    }

    public private(set) var rows: [BookmarkRow] = []
    public private(set) var totalCount = 0
    public private(set) var phase = ListPhase.loading
    public private(set) var isRefreshing = false
    public private(set) var refreshError: WaiveraError?
    /// The list came from the slow per-conversation fallback.
    public private(set) var usedFallback = false
    /// Undo could not save the message again.
    public private(set) var restoreError: WaiveraError?

    @ObservationIgnored private let bookmarks: any BookmarksRepository
    @ObservationIgnored private let realtime: any RealtimeStatusRepository
    @ObservationIgnored private var resource = Resource<BookmarkList>()
    @ObservationIgnored private var hidden = Set<Int>()
    @ObservationIgnored private var refreshInFlight = false

    public init(bookmarks: any BookmarksRepository, realtime: any RealtimeStatusRepository) {
        self.bookmarks = bookmarks
        self.realtime = realtime
    }

    public convenience init(environment: DataEnvironment) {
        self.init(bookmarks: environment.bookmarks, realtime: environment.realtimeStatus)
    }

    public func run() async {
        async let list: Void = observeBookmarks()
        async let reconnects: Void = onReconnect(realtime) { await self.refresh() }
        await refresh()
        _ = await (list, reconnects)
    }

    private func observeBookmarks() async {
        for await value in bookmarks.bookmarks() { apply(value) }
    }

    public func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        isRefreshing = true
        derive()
        await bookmarks.refresh()
        refreshInFlight = false
        isRefreshing = false
        derive()
    }

    /// Hides the row at once, then removes the bookmark. The screen offers Undo on `.removed`.
    public func remove(_ row: BookmarkRow) async -> RemoveOutcome {
        guard !hidden.contains(row.messageID) else { return .ignored }
        hidden.insert(row.messageID)
        derive()
        do {
            let saved = try await bookmarks.toggle(messageId: row.messageID, conversationId: row.conversationID)
            // Saved instead means the server had already dropped it; toggle back to removed.
            if saved { _ = try? await bookmarks.toggle(messageId: row.messageID, conversationId: row.conversationID) }
            // The row stays hidden until the list no longer has it, so it never flickers back.
            pruneHidden()
            return .removed
        } catch {
            hidden.remove(row.messageID)
            derive()
            return .failed(WaiveraError.from(error))
        }
    }

    /// Saves the message again after a remove.
    public func undoRemove(_ row: BookmarkRow) async {
        restoreError = nil
        hidden.remove(row.messageID)
        do {
            let saved = try await bookmarks.toggle(messageId: row.messageID, conversationId: row.conversationID)
            if !saved { _ = try? await bookmarks.toggle(messageId: row.messageID, conversationId: row.conversationID) }
        } catch {
            restoreError = WaiveraError.from(error)
        }
    }

    public func dismissRestoreError() {
        restoreError = nil
    }

    private func apply(_ value: Resource<BookmarkList>) {
        resource = value
        pruneHidden()
    }

    private func pruneHidden() {
        let present = Set((resource.value?.bookmarks ?? []).map(\.id))
        hidden.formIntersection(present)
        derive()
    }

    private func derive() {
        let all = BookmarkRules.rows(resource.value?.bookmarks ?? []).filter { !hidden.contains($0.messageID) }
        let shown = all.filter { BookmarkRules.matches($0, query: query, words: searchWords) }
        rows = shown
        totalCount = all.count
        usedFallback = resource.value?.usedFallback ?? false
        refreshError = resource.value == nil ? nil : resource.error
        phase =
            if !all.isEmpty {
                shown.isEmpty ? .noMatches : .content
            } else if let error = resource.error, resource.value == nil {
                .failed(error)
            } else if resource.phase == .loaded || (resource.value != nil && !isRefreshing) {
                .empty
            } else {
                .loading
            }
    }
}
