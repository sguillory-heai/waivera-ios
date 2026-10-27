import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// A staff member in the picker.
struct PersonOption: Identifiable, Sendable, Hashable {
    let id: String
    var name: String
    var isSelected: Bool
}

enum NewChatAction: Sendable, Hashable {
    /// Zero or one person: open (or start) the direct message.
    case openChat
    case createGroup
}

enum NewChatContent: Sendable, Hashable {
    /// Directory not loaded yet; the skeleton shows after ~300 ms.
    case loading
    /// The directory could not be loaded and nothing is cached.
    case error(WaiveraError)
    /// Nobody matches the search (or the directory is empty).
    case empty
    case people
}

struct NewChatState: Sendable, Hashable {
    var content = NewChatContent.loading
    var people: [PersonOption] = []
    var selectedCount = 0
    var isCreating = false
    /// Opening or creating the conversation failed.
    var error: WaiveraError?

    var action: NewChatAction { selectedCount <= 1 ? .openChat : .createGroup }
    var canSubmit: Bool { selectedCount > 0 && !isCreating }
}

/// New chat and the people picker (02 §7).
///
/// Submitting first looks for an existing non-channel conversation whose other participants
/// are exactly the selection (order-insensitive, same size, 11-pitfalls #5) and opens it with
/// no request. Otherwise it creates the conversation. When that fails (notably sprout_api's
/// 409 for a participant set that already exists), it refreshes the inbox from the same
/// endpoint the list reads and matches again before showing the error.
@MainActor
@Observable
final class NewChatModel {
    /// The directory is refetched when older than this (02 §7 `staleTime`).
    static let staleAfter: TimeInterval = 60

    private(set) var state = NewChatState()

    var query = "" {
        didSet { if query != oldValue { rebuild() } }
    }

    @ObservationIgnored private let people: any PeopleRepository
    @ObservationIgnored private let conversations: any ConversationsRepository
    @ObservationIgnored private let session: any SessionRepository
    @ObservationIgnored private let clock: any WaiveraClock

    @ObservationIgnored private var directory = Resource<[DirectoryPerson]>()
    @ObservationIgnored private var inbox: [Conversation] = []
    @ObservationIgnored private var viewerId: String?
    /// In the order people were picked, so the request lists them as chosen.
    @ObservationIgnored private var selected: [String] = []
    @ObservationIgnored private var checkedStaleness = false

    init(
        people: any PeopleRepository,
        conversations: any ConversationsRepository,
        session: any SessionRepository,
        clock: any WaiveraClock
    ) {
        self.people = people
        self.conversations = conversations
        self.session = session
        self.clock = clock
        viewerId = session.currentState.user?.id
    }

    convenience init(environment: DataEnvironment, clock: any WaiveraClock = SystemClock()) {
        self.init(
            people: environment.people,
            conversations: environment.conversations,
            session: environment.session,
            clock: clock
        )
    }

    // MARK: Lifecycle

    func start() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.observeDirectory() }
            group.addTask { await self.observeInbox() }
            group.addTask { await self.observeSession() }
        }
    }

    func retryLoad() async {
        await people.refresh()
    }

    // MARK: Actions

    func toggle(_ userId: String) {
        guard !state.isCreating else { return }
        if let index = selected.firstIndex(of: userId) {
            selected.remove(at: index)
        } else {
            selected.append(userId)
        }
        state.error = nil
        rebuild()
    }

    /// Opens or creates the conversation; returns its id, or `nil` with `state.error` set.
    func submit() async -> Int? {
        let selection = selected
        guard !selection.isEmpty, !state.isCreating else { return nil }
        if let existing = Self.match(selection, in: inbox, viewerId: viewerId) { return finish(existing) }
        state.isCreating = true
        state.error = nil
        do {
            let created = try await conversations.createConversation(participantIds: Self.unique(selection))
            return finish(created.id)
        } catch {
            // 409 or anything else: the set may exist already. Refresh and match once more.
            await conversations.refresh()
            let fresh = await latestInbox()
            if let recovered = Self.match(selection, in: fresh, viewerId: viewerId) { return finish(recovered) }
            state.isCreating = false
            state.error = WaiveraError.from(error)
            return nil
        }
    }

    /// The sheet is closing: forget the search and selection.
    func reset() {
        guard !state.isCreating else { return }
        selected = []
        query = ""
        state.error = nil
        rebuild()
    }

    private func finish(_ conversationId: Int) -> Int {
        selected = []
        query = ""
        state.isCreating = false
        state.error = nil
        rebuild()
        return conversationId
    }

    // MARK: Matching

    /// The existing non-channel conversation whose other participants are exactly `selection`.
    nonisolated static func match(_ selection: [String], in inbox: [Conversation], viewerId: String?) -> Int? {
        let wanted = Set(selection).subtracting(viewerId.map { [$0] } ?? [])
        guard !wanted.isEmpty else { return nil }
        return inbox.first { conversation in
            guard conversation.kind == .direct || conversation.kind == .group else { return false }
            let others = conversation.participants.map(\.id).filter { $0 != viewerId }
            return others.count == wanted.count && Set(others) == wanted
        }?.id
    }

    nonisolated static func unique(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { seen.insert($0).inserted }
    }

    // MARK: Streams

    private func observeDirectory() async {
        for await next in people.directory() {
            directory = next
            rebuild()
            if !checkedStaleness, next.phase != .loading {
                checkedStaleness = true
                if isStale(next) { Task { await self.people.refresh() } }
            }
        }
    }

    private func observeInbox() async {
        for await next in conversations.conversations() {
            inbox = next.value ?? []
        }
    }

    private func observeSession() async {
        for await next in session.states() {
            viewerId = next.user?.id
            rebuild()
        }
    }

    /// Streams replay their current value, so the first element is the inbox right now.
    private func latestInbox() async -> [Conversation] {
        for await next in conversations.conversations() {
            return next.value ?? inbox
        }
        return inbox
    }

    private func isStale(_ resource: Resource<[DirectoryPerson]>) -> Bool {
        guard let updatedAt = resource.updatedAt else { return true }
        return clock.now.timeIntervalSince(updatedAt) >= Self.staleAfter
    }

    // MARK: State

    private func rebuild() {
        var next = state
        let chosen = Set(selected)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let everyone = (directory.value ?? []).filter { person in
            !person.id.trimmingCharacters(in: .whitespaces).isEmpty && person.id != viewerId
        }
        next.people = everyone.compactMap { person -> PersonOption? in
            let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard needle.isEmpty || name.lowercased().contains(needle) else { return nil }
            return PersonOption(id: person.id, name: name, isSelected: chosen.contains(person.id))
        }
        next.selectedCount = selected.count
        if directory.value == nil {
            next.content = directory.error.map(NewChatContent.error) ?? .loading
        } else {
            next.content = next.people.isEmpty ? .empty : .people
        }
        if next != state { state = next }
    }
}
