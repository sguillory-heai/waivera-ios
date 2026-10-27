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

    public nonisolated func profile() -> AsyncStream<Resource<OwnProfile>> { cell.stream() }

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

    /// Sections load independently; the screen fails only when the main record fails.
    public func refresh() async {
        guard let user = context.currentUser else {
            phase = .failed(.signedOut)
            publish()
            return
        }
        let current = generation
        phase = .loading
        publish()
        let api = api
        async let details = api.employeeProfile(employeeId: user.id)
        async let timeOff = api.timeOffForProfile(userId: user.id)
        async let files = api.employeeFiles(userId: user.id)
        async let organizations = api.organizationDetails()
        do {
            let profile = ProfileMapper.profile(try await details)
            var next = OwnProfile(profile: profile)
            next.timeOff = (try? await timeOff).map(ProfileMapper.timeOff)
            next.files = Array(
                ((try? await files) ?? []).map(ProfileMapper.file)
                    .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
                    .prefix(Self.visibleFiles)
            )
            next.organization = Self.organization(user.organization, in: (try? await organizations) ?? [])
            guard generation == current else { return }
            value = next
            phase = .loaded
            updatedAt = clock.now
            let store = store
            let cached = CachedProfile(profile: next)
            writes.enqueue { await store.save(cached, for: .profile) }
        } catch {
            guard generation == current else { return }
            phase = .failed(WaiveraError.from(error))
        }
        publish()
    }

    /// Matched by id only; a name match could pick another tenant (08 §5).
    static func organization(_ session: Organization?, in list: [OrganizationDto]) -> Organization? {
        guard let session else { return nil }
        guard let match = list.first(where: { $0.id == session.id }) else { return session }
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
