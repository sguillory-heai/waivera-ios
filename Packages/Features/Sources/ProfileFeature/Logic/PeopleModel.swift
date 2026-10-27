import Foundation
import Observation
import WaiveraAPI
import WaiveraData

public struct PersonRow: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var celebration: Celebration?
}

/// Directory rules from 06 §C1, pure so they are unit tested.
public enum PeopleFilter {
    /// Drops entries without an id or a name and the signed-in person, then matches `query`
    /// case- and diacritic-insensitively against the name.
    ///
    /// "Is this me" uses the backend id everywhere else; here the Firebase uid is also excluded
    /// because the directory has been seen to carry either (06 §C3). Excluding never attributes
    /// anything to the wrong person, so the wider match is safe.
    public static func apply(_ people: [DirectoryPerson], me: CurrentUser?, query: String) -> [DirectoryPerson] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        return people.filter { person in
            guard person.id.nonBlank != nil, person.name.nonBlank != nil else { return false }
            if let me, person.id == me.id || person.id == me.firebaseUid { return false }
            guard seen.insert(person.id).inserted else { return false }
            return needle.isEmpty
                || person.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// The staff directory. Rows open the person's profile.
@MainActor
@Observable
public final class PeopleModel {
    public var query = "" {
        didSet { if query != oldValue { derive() } }
    }

    public private(set) var rows: [PersonRow] = []
    /// People in the directory before the search, so the empty state can say which case it is.
    public private(set) var totalCount = 0
    public private(set) var phase = ListPhase.loading
    public private(set) var isRefreshing = false
    /// A refresh failed while the directory is on screen.
    public private(set) var refreshError: WaiveraError?

    @ObservationIgnored private let people: any PeopleRepository
    @ObservationIgnored private let session: any SessionRepository
    @ObservationIgnored private let calendar: any CalendarRepository
    @ObservationIgnored private let realtime: any RealtimeStatusRepository
    @ObservationIgnored private var resource = Resource<[DirectoryPerson]>()
    @ObservationIgnored private var me: CurrentUser?
    @ObservationIgnored private var milestones = MilestoneIndex.empty
    @ObservationIgnored private var refreshInFlight = false

    public init(
        people: any PeopleRepository,
        session: any SessionRepository,
        calendar: any CalendarRepository,
        realtime: any RealtimeStatusRepository
    ) {
        self.people = people
        self.session = session
        self.calendar = calendar
        self.realtime = realtime
        me = session.currentState.user
    }

    public convenience init(environment: DataEnvironment) {
        self.init(
            people: environment.people,
            session: environment.session,
            calendar: environment.calendar,
            realtime: environment.realtimeStatus
        )
    }

    public func run() async {
        async let directory: Void = observeDirectory()
        async let sessions: Void = observeSession()
        async let milestones: Void = observeMilestones()
        async let reconnects: Void = onReconnect(realtime) { await self.refresh() }
        await refresh()
        _ = await (directory, sessions, milestones, reconnects)
    }

    private func observeDirectory() async {
        for await value in people.directory() { apply(value) }
    }

    private func observeSession() async {
        for await state in session.states() { apply(user: state.user) }
    }

    private func observeMilestones() async {
        for await index in calendar.milestones() { apply(milestones: index.value ?? .empty) }
    }

    /// Header refresh and pull-to-refresh; a refresh already running is not restarted.
    public func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        isRefreshing = true
        refreshError = nil
        derive()
        await people.refresh()
        refreshInFlight = false
        isRefreshing = false
        derive()
    }

    private func apply(_ value: Resource<[DirectoryPerson]>) {
        resource = value
        derive()
    }

    private func apply(user: CurrentUser?) {
        guard user != me else { return }
        me = user
        derive()
    }

    private func apply(milestones index: MilestoneIndex) {
        milestones = index
        derive()
    }

    private func derive() {
        let all = resource.value ?? []
        let everyone = PeopleFilter.apply(all, me: me, query: "")
        let matches = query.nonBlank == nil ? everyone : PeopleFilter.apply(all, me: me, query: query)
        let today = calendar.today()
        rows = matches.map {
            PersonRow(id: $0.id, name: $0.name, celebration: milestones.celebration(for: $0.id, on: today))
        }
        totalCount = everyone.count
        refreshError = resource.value == nil ? nil : resource.error
        phase =
            if !everyone.isEmpty {
                matches.isEmpty ? .noMatches : .content
            } else if let error = resource.error, resource.value == nil {
                .failed(error)
            } else if resource.phase == .loaded || (resource.value != nil && !isRefreshing) {
                .empty
            } else {
                .loading
            }
    }
}
