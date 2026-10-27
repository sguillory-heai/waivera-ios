import Foundation
import WaiveraAPI

/// The staff directory from `get-username-list` (never the combined list, which includes
/// waiver participants, 06 §C1) and person details.
public actor LivePeopleRepository: PeopleRepository {
    private let api: APIClient
    private let store: any LocalStore
    private let clock: any WaiveraClock
    private let cell = StateCell(Resource<[DirectoryPerson]>())
    private var people: [DirectoryPerson]?
    private var details: [String: PersonProfile] = [:]
    private var phase: ResourcePhase = .idle
    private var updatedAt: Date?
    private var generation = 0
    private let writes = SerialQueue()

    public init(api: APIClient, store: any LocalStore, clock: any WaiveraClock) {
        self.api = api
        self.store = store
        self.clock = clock
    }

    public nonisolated func directory() -> AsyncStream<Resource<[DirectoryPerson]>> { cell.stream() }

    public func begin() async {
        guard people == nil, let cached = await store.load([DirectoryPerson].self, for: .directory) else { return }
        people = cached
        publish()
    }

    /// Sign-out: drops state and waits for queued cache writes so none lands after the wipe.
    public func reset() async {
        generation += 1
        people = nil
        details.removeAll()
        phase = .idle
        updatedAt = nil
        cell.set(Resource())
        await writes.drain()
    }

    public func refresh() async {
        let current = generation
        phase = .loading
        publish()
        do {
            let rows = try await api.usernameList()
            guard generation == current else { return }
            var seen = Set<String>()
            let directory = rows.compactMap { row -> DirectoryPerson? in
                guard let name = row.userName?.trimmed, !name.isEmpty, seen.insert(row.userId).inserted else {
                    return nil
                }
                return DirectoryPerson(id: row.userId, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            people = directory
            phase = .loaded
            updatedAt = clock.now
            let store = store
            writes.enqueue { await store.save(directory, for: .directory) }
        } catch {
            guard generation == current else { return }
            phase = .failed(WaiveraError.from(error))
        }
        publish()
    }

    public func person(id: String) async throws -> PersonProfile {
        do {
            let profile = ProfileMapper.person(try await api.userDetails(userId: id))
            details[id] = profile
            return profile
        } catch {
            if let cached = details[id] { return cached }
            throw WaiveraError.from(error)
        }
    }

    private func publish() {
        cell.set(Resource(value: people, phase: phase, updatedAt: updatedAt))
    }
}
