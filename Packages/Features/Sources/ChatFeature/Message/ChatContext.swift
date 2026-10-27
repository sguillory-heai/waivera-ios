import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// What the conversation and the thread both observe besides their messages: the viewer, the
/// conversation row, saved messages, the directory and the hub connection.
@MainActor
final class ChatContext {
    enum Change: Sendable {
        case viewer, conversation, bookmarks, names, subtitle
    }

    private(set) var viewerId: String?
    private(set) var conversation: Conversation?
    /// `nil` until bookmarks load; messages keep their own flag until then.
    private(set) var savedIds: Set<Int>?
    private(set) var directory: [DirectoryPerson] = []
    private(set) var subtitle: ConnectionSubtitle?
    private(set) var isConnected = false

    private let conversationId: Int
    private var requestedDetail = false

    init(conversationId: Int) {
        self.conversationId = conversationId
    }

    /// Observes until cancelled, reporting each change on the main actor.
    func run(_ data: DataEnvironment, onChange: @escaping @MainActor (Change) -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await state in data.session.states() {
                    await self.setViewer(state.user?.id, onChange)
                }
            }
            group.addTask {
                for await resource in data.conversations.conversations() {
                    await self.receive(resource, data: data, onChange)
                }
            }
            group.addTask {
                for await resource in data.bookmarks.bookmarks() {
                    await self.setSaved(resource.value.map { Set($0.bookmarks.map(\.id)) }, onChange)
                }
            }
            group.addTask {
                for await resource in data.people.directory() {
                    await self.setDirectory(resource.value, onChange)
                }
            }
            group.addTask {
                for await banner in data.realtimeStatus.banner() {
                    await self.setSubtitle(ConnectionSubtitle(banner), onChange)
                }
            }
            group.addTask {
                for await status in data.realtimeStatus.statuses() {
                    await self.setConnected(status.isConnected)
                }
            }
        }
    }

    /// Fetches the row directly when the inbox does not hold it (a deep link to an old chat).
    func loadDetail(_ data: DataEnvironment, onChange: @MainActor (Change) -> Void) async {
        guard let row = try? await data.conversations.conversation(id: conversationId) else {
            requestedDetail = false
            return
        }
        guard conversation == nil else { return }
        conversation = row
        onChange(.conversation)
    }

    private func receive(
        _ resource: Resource<[Conversation]>,
        data: DataEnvironment,
        _ onChange: @MainActor (Change) -> Void
    ) async {
        if let row = resource.value?.first(where: { $0.id == conversationId }) {
            guard row != conversation else { return }
            conversation = row
            onChange(.conversation)
        } else if conversation == nil, !requestedDetail {
            requestedDetail = true
            await loadDetail(data, onChange: onChange)
        }
    }

    private func setViewer(_ id: String?, _ onChange: @MainActor (Change) -> Void) {
        guard id != viewerId else { return }
        viewerId = id
        onChange(.viewer)
    }

    private func setSaved(_ ids: Set<Int>?, _ onChange: @MainActor (Change) -> Void) {
        guard let ids, ids != savedIds else { return }
        savedIds = ids
        onChange(.bookmarks)
    }

    private func setDirectory(_ people: [DirectoryPerson]?, _ onChange: @MainActor (Change) -> Void) {
        guard let people, people != directory else { return }
        directory = people
        onChange(.names)
    }

    private func setSubtitle(_ value: ConnectionSubtitle?, _ onChange: @MainActor (Change) -> Void) {
        guard value != subtitle else { return }
        subtitle = value
        onChange(.subtitle)
    }

    private func setConnected(_ value: Bool) {
        isConnected = value
    }

    /// The message with the viewer's saved state applied, once bookmarks are known.
    func marked(_ message: ChatMessage) -> ChatMessage {
        guard let savedIds else { return message }
        var copy = message
        copy.isBookmarked = savedIds.contains(message.id)
        return copy
    }

    func names(messages: [ChatMessage]) -> [String: String] {
        ChatNames.names(directory: directory, participants: conversation?.participants ?? [], messages: messages)
    }
}

/// Parsed documents by message, reused while the message's content is unchanged; parsing
/// stringified documents on every emission would be wasted work in long timelines.
@MainActor
final class RichDocumentCache {
    private var entries: [Int: (fingerprint: Int, document: RichDocument?)] = [:]

    func document(for message: ChatMessage) -> RichDocument? {
        var hasher = Hasher()
        hasher.combine(message.doc)
        hasher.combine(message.content)
        hasher.combine(message.plaintext)
        let fingerprint = hasher.finalize()
        if let entry = entries[message.id], entry.fingerprint == fingerprint { return entry.document }
        let document = TipTapParser.document(for: message)
        entries[message.id] = (fingerprint, document)
        return document
    }
}
