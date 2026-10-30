import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// One person in a group's member list. `name` is empty when the server sent no name; the row
/// shows a fallback. There is no role: conversation participants carry only a name, an email and
/// an avatar, and a group has no owner (spec §9.2).
struct MemberRow: Identifiable, Hashable, Sendable {
    var userId: String
    var name: String
    var isMe: Bool

    var id: String { userId }
}

/// Which block the members list shows.
enum MembersContent: Hashable, Sendable {
    case loading
    /// Nothing cached and the fetch failed.
    case error(WaiveraError)
    /// No members, or none matching the search.
    case empty
    case members
}

struct GroupMembersState: Hashable, Sendable {
    var content = MembersContent.loading
    /// The rows after the search: me first, then by name.
    var rows: [MemberRow] = []
    /// Everyone in the group before the search: the count under the title.
    var totalCount = 0
    var query = ""
    var connection: ConnectionSubtitle?
    /// The person whose direct chat is being opened; their Message button shows it is busy.
    var openingChatWith: String?
    /// Opening a direct chat failed: New chat's copy for the typed error.
    var messageError: WaiveraError?

    /// Search shows only on a long list: more than `MemberRules.searchFrom` people.
    var showsSearch: Bool { totalCount > MemberRules.searchFrom }

    /// The list is filtered down to nothing; the empty state offers to clear the search.
    var isNoMatch: Bool { content == .empty && totalCount > 0 }
}

/// The member list's rules, kept pure so they are tested on Linux.
enum MemberRules {
    /// Search shows when a group has more members than this.
    static let searchFrom = 10

    /// Everyone in `conversation` with an id, once each: the signed-in person first, then
    /// everyone else by name ignoring case, then by id so equal names keep a stable order.
    static func rows(_ conversation: Conversation, myUserId: String?) -> [MemberRow] {
        var seen: Set<String> = []
        return conversation.participants
            .filter { !$0.id.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert($0.id).inserted }
            .map { MemberRow(userId: $0.id, name: $0.fullName ?? "", isMe: $0.id == myUserId) }
            .sorted { lhs, rhs in
                if lhs.isMe != rhs.isMe { return lhs.isMe }
                let left = lhs.name.lowercased()
                let right = rhs.name.lowercased()
                if left != right { return left < right }
                return lhs.userId < rhs.userId
            }
    }

    /// `rows` whose name holds `query`, ignoring case and surrounding spaces.
    static func filter(_ rows: [MemberRow], query: String) -> [MemberRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return rows }
        return rows.filter { $0.name.lowercased().contains(needle) }
    }
}

/// What the members screen reads and does, narrowed from the data layer so tests drive it.
struct GroupMembersSource: Sendable {
    var inbox: @Sendable () -> AsyncStream<Resource<[Conversation]>>
    /// The conversation's detail, for a group the inbox does not hold.
    var detail: @Sendable (_ id: Int) async throws -> Conversation
    /// Refetches the inbox, which carries every group's participants.
    var refresh: @Sendable () async -> Void
    /// Get-or-create the direct chat with one person (New chat's call); returns its id.
    var openDirect: @Sendable (_ userId: String) async throws -> Int
    var viewer: @Sendable () -> AsyncStream<String?>
    var banner: @Sendable () -> AsyncStream<ConnectionBanner>
    var statuses: @Sendable () -> AsyncStream<RealtimeStatus>
    var retryConnection: @Sendable () async -> Void
}

extension GroupMembersSource {
    init(environment data: DataEnvironment) {
        let conversations = data.conversations
        let session = data.session
        let realtime = data.realtimeStatus
        self.init(
            inbox: { conversations.conversations() },
            detail: { try await conversations.conversation(id: $0) },
            refresh: { await conversations.refresh() },
            openDirect: { try await conversations.openDirectConversation(with: $0).id },
            viewer: {
                let states = session.states()
                return AsyncStream { continuation in
                    let task = Task {
                        for await state in states { continuation.yield(state.user?.id) }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            banner: { realtime.banner() },
            statuses: { realtime.statuses() },
            retryConnection: { await realtime.retryNow() }
        )
    }
}

/// A group's members (v7 item 4), opened from the "N members" button in the conversation
/// header. The list comes from the conversation's own participants, so a cached group shows at
/// once and stays current as the conversation updates. Message opens the direct chat through
/// the same call New chat makes for one person, which reuses the chat when it exists. Silent:
/// nothing here vibrates.
@MainActor
@Observable
final class GroupMembersModel {
    let channelID: Int
    private(set) var state = GroupMembersState()

    var query: String {
        get { state.query }
        set {
            guard newValue != state.query else { return }
            state.query = newValue
            rebuild()
        }
    }

    @ObservationIgnored private let source: GroupMembersSource
    @ObservationIgnored private var conversation: Conversation?
    @ObservationIgnored private var viewerId: String?
    @ObservationIgnored private var inboxLoaded = false
    @ObservationIgnored private var requestedDetail = false
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var loadError: WaiveraError?
    @ObservationIgnored private var lastConnected: Bool?

    init(channelID: Int, source: GroupMembersSource) {
        self.channelID = channelID
        self.source = source
    }

    /// A model that only displays `state`, for previews and snapshot tests.
    init(preview: GroupMembersState) {
        channelID = 0
        source = GroupMembersSource(
            inbox: { AsyncStream { $0.finish() } },
            detail: { _ in throw WaiveraError.notFound },
            refresh: {},
            openDirect: { _ in throw WaiveraError.notFound },
            viewer: { AsyncStream { $0.finish() } },
            banner: { AsyncStream { $0.finish() } },
            statuses: { AsyncStream { $0.finish() } },
            retryConnection: {}
        )
        state = preview
    }

    // MARK: Lifecycle

    /// Observes until cancelled (`.task`).
    func run() async {
        let source = source
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await resource in source.inbox() { await self.receive(resource) }
            }
            group.addTask {
                for await id in source.viewer() { await self.setViewer(id) }
            }
            group.addTask {
                for await banner in source.banner() { await self.setConnection(ConnectionSubtitle(banner)) }
            }
            group.addTask {
                for await status in source.statuses() { await self.receive(status) }
            }
        }
    }

    /// Try again after a failed load; a load already running is not restarted.
    func retry() async {
        await load()
    }

    func retryConnection() async {
        await source.retryConnection()
    }

    // MARK: Message

    /// Opens `userId`'s direct chat, or starts it; one at a time, and never with myself.
    /// Returns the conversation to open, or `nil` with `state.messageError` set.
    func message(_ userId: String) async -> Int? {
        guard state.openingChatWith == nil else { return nil }
        guard !state.rows.contains(where: { $0.userId == userId && $0.isMe }), userId != viewerId else { return nil }
        state.openingChatWith = userId
        state.messageError = nil
        do {
            let id = try await source.openDirect(userId)
            state.openingChatWith = nil
            return id
        } catch {
            state.openingChatWith = nil
            state.messageError = WaiveraError.from(error)
            return nil
        }
    }

    func dismissMessageError() {
        state.messageError = nil
    }

    // MARK: Streams

    private func receive(_ resource: Resource<[Conversation]>) async {
        if let row = resource.value?.first(where: { $0.id == channelID }) {
            conversation = row
            loadError = nil
            rebuild()
            return
        }
        if resource.value != nil || resource.phase == .loaded { inboxLoaded = true }
        if resource.error != nil { inboxLoaded = true }
        guard inboxLoaded, conversation == nil, !requestedDetail else { return }
        requestedDetail = true
        await load()
    }

    private func setViewer(_ id: String?) {
        guard id != viewerId else { return }
        viewerId = id
        rebuild()
    }

    private func setConnection(_ value: ConnectionSubtitle?) {
        guard value != state.connection else { return }
        state.connection = value
    }

    /// What changed while the hub was down (someone joined or left) arrives with a refetch.
    private func receive(_ status: RealtimeStatus) async {
        let connected = status.isConnected
        defer { lastConnected = connected }
        guard let last = lastConnected, !last, connected else { return }
        await load()
    }

    /// The inbox first, since it carries the participants; the detail when the inbox has no row
    /// for this group (a link to an old chat).
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        rebuild()
        await source.refresh()
        if conversation == nil || requestedDetail {
            do {
                let row = try await source.detail(channelID)
                conversation = row
            } catch {
                if conversation == nil { loadError = WaiveraError.from(error) }
            }
        }
        isLoading = false
        rebuild()
    }

    private func rebuild() {
        var next = state
        let all = conversation.map { MemberRules.rows($0, myUserId: viewerId) } ?? []
        let shown = MemberRules.filter(all, query: state.query)
        next.rows = shown
        next.totalCount = all.count
        if conversation == nil {
            next.content = loadError.flatMap { isLoading ? nil : MembersContent.error($0) } ?? .loading
        } else {
            next.content = shown.isEmpty ? .empty : .members
        }
        if next != state { state = next }
    }
}
