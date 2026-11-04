import Foundation
import WaiveraAPI

/// The staff directory from `GET /api/users`, the list the web chat uses: staff in the caller's
/// own organization, without the caseload participants that list also carries (06 §C1). Never
/// `get-username-list`, which spans every organization. Also person details.
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

    nonisolated public func directory() -> AsyncStream<Resource<[DirectoryPerson]>> { cell.stream() }

    public func begin() async {
        await store.remove(.legacyDirectory)
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
            let rows = try await api.organizationUsers(onlyActive: true)
            guard generation == current else { return }
            var seen = Set<String>()
            let directory = rows.compactMap { row -> DirectoryPerson? in
                guard let id = row.id?.trimmed, !id.isEmpty, Self.isStaff(row),
                    let name = Self.name(of: row), seen.insert(id).inserted
                else {
                    return nil
                }
                return DirectoryPerson(id: id, name: name)
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

    private static func isStaff(_ row: UserInfoResponse) -> Bool {
        row.isParticipant != true && row.deactivated != true
            && row.employeeRole?.trimmed.caseInsensitiveCompare("Participant") != .orderedSame
    }

    /// Display name, else first and last name, else email, as on Android.
    private static func name(of row: UserInfoResponse) -> String? {
        if let display = row.displayName?.trimmed, !display.isEmpty { return display }
        let full = [row.firstName, row.lastName]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !full.isEmpty { return full }
        return row.email?.trimmed.nilIfEmpty
    }

    private func publish() {
        cell.set(Resource(value: people, phase: phase, updatedAt: updatedAt))
    }
}
