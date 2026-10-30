import Foundation
import WaiveraAPI

/// The own-profile screen: details, time off, files and organization, all keyed by the
/// backend id (08 §1).
public actor LiveProfileRepository: ProfileRepository {
    static let visibleFiles = 5

    private let api: APIClient
    private let context: SessionContext
    private let store: any LocalStore
    private let clock: any WaiveraClock
    private let cell = StateCell(Resource<OwnProfile>())
    private var value: OwnProfile?
    private var phase: ResourcePhase = .idle
    private var updatedAt: Date?
    private var generation = 0
    private let writes = SerialQueue()

    public init(api: APIClient, context: SessionContext, store: any LocalStore, clock: any WaiveraClock) {
        self.api = api
        self.context = context
        self.store = store
        self.clock = clock
    }

    nonisolated public func profile() -> AsyncStream<Resource<OwnProfile>> { cell.stream() }

    public func begin() async {
        guard value == nil, let cached = await store.load(CachedProfile.self, for: .profile) else { return }
        value = cached.ownProfile
        publish()
    }

    /// Sign-out: drops state and waits for queued cache writes so none lands after the wipe.
    public func reset() async {
        generation += 1
        value = nil
        phase = .idle
        updatedAt = nil
        cell.set(Resource())
        await writes.drain()
    }

    /// Sections load independently (08 §2-4): the screen fails only when the main record does;
    /// time off and files carry their own phase, so a failed card shows its own Retry.
    public func refresh() async {
        guard let user = context.currentUser else {
            phase = .failed(.signedOut)
            publish()
            return
        }
        let current = generation
        phase = .loading
        value?.sections = OwnProfile.SectionPhases(timeOff: .loading, files: .loading)
        publish()
        let api = api
        async let details = api.employeeProfile(employeeId: user.id)
        async let timeOff = Self.result { try await api.timeOffForProfile(userId: user.id) }
        async let files = Self.result { try await api.employeeFiles(userId: user.id) }
        async let organizations = try? api.organizationDetails()
        do {
            var profile = ProfileMapper.profile(try await details)
            profile.scId = user.scId
            var next = OwnProfile(profile: profile)
            apply(await timeOff, to: &next)
            apply(await files, to: &next)
            next.organization = Self.organization(user.organization, in: await organizations ?? [])
            guard generation == current else { return }
            value = next
            phase = .loaded
            updatedAt = clock.now
            save(next)
        } catch {
            guard generation == current else { return }
            phase = .failed(WaiveraError.from(error))
            value?.sections = OwnProfile.SectionPhases(timeOff: .idle, files: .idle)
        }
        publish()
    }

    /// One card's Retry: reloads it alone and leaves the rest of the screen as it is.
    public func refresh(section: ProfileSection) async {
        guard let user = context.currentUser, var next = value else { return }
        let current = generation
        switch section {
        case .timeOff: next.sections.timeOff = .loading
        case .files: next.sections.files = .loading
        }
        value = next
        publish()
        let api = api
        switch section {
        case .timeOff: apply(await Self.result { try await api.timeOffForProfile(userId: user.id) }, to: &next)
        case .files: apply(await Self.result { try await api.employeeFiles(userId: user.id) }, to: &next)
        }
        guard generation == current, var latest = value else { return }
        switch section {
        case .timeOff:
            latest.timeOff = next.timeOff
            latest.sections.timeOff = next.sections.timeOff
        case .files:
            latest.files = next.files
            latest.sections.files = next.sections.files
        }
        value = latest
        save(latest)
        publish()
    }

    private func apply(_ result: Result<[TimeOffProfileItemDto], WaiveraError>, to profile: inout OwnProfile) {
        switch result {
        case .success(let rows):
            profile.timeOff = ProfileMapper.timeOff(rows)
            profile.sections.timeOff = .loaded
        case .failure(let error):
            profile.timeOff = value?.timeOff
            profile.sections.timeOff = .failed(error)
        }
    }

    private func apply(_ result: Result<[EmployeeFileDto], WaiveraError>, to profile: inout OwnProfile) {
        switch result {
        case .success(let rows):
            profile.files = Array(
                rows.map(ProfileMapper.file)
                    .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
                    .prefix(Self.visibleFiles)
            )
            profile.sections.files = .loaded
        case .failure(let error):
            profile.files = value?.files ?? []
            profile.sections.files = .failed(error)
        }
    }

    private static func result<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, WaiveraError> {
        do {
            return .success(try await work())
        } catch {
            return .failure(WaiveraError.from(error))
        }
    }

    private func save(_ profile: OwnProfile) {
        let store = store
        let cached = CachedProfile(profile: profile)
        writes.enqueue { await store.save(cached, for: .profile) }
    }

    /// Matched by id only: a name match could pick another tenant, and a miss is "details
    /// unavailable", never the session's copy (08 §5).
    static func organization(_ session: Organization?, in list: [OrganizationDto]) -> Organization? {
        guard let session, let match = list.first(where: { $0.id == session.id }) else { return nil }
        var organization = session
        organization.name = match.name?.nilIfBlank ?? session.name
        organization.address = match.address?.nilIfBlank
        organization.contactNumber = match.contactNumber?.nilIfBlank
        return organization
    }

    private func publish() {
        cell.set(Resource(value: value, phase: phase, updatedAt: updatedAt))
    }
}

/// `OwnProfile` is not `Codable` because its parts are cached together.
private struct CachedProfile: Codable, Sendable {
    var profile: EmployeeProfile?
    var timeOff: TimeOffOverview?
    var files: [EmployeeFile]
    var organization: Organization?

    init(profile: OwnProfile) {
        self.profile = profile.profile
        timeOff = profile.timeOff
        files = profile.files
        organization = profile.organization
    }

    var ownProfile: OwnProfile {
        OwnProfile(profile: profile, timeOff: timeOff, files: files, organization: organization)
    }
}
