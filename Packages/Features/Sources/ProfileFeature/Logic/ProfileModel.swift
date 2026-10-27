import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// The signed-in person's profile (08 §1-5).
///
/// The backend user id is required: without it the screen shows one "profile unavailable"
/// state instead of a page of dashes (Expo bug, 08 §1). A failed refresh keeps the shown
/// profile and reports the failure inline; Refresh and Retry show a busy state until the
/// repository settles.
@MainActor
@Observable
public final class ProfileModel {
    public enum Phase: Equatable, Sendable {
        /// No backend session id.
        case unavailable
        case loading
        /// Nothing to show and the load failed.
        case failed(WaiveraError)
        case loaded
    }

    public private(set) var phase: Phase
    public private(set) var user: CurrentUser?
    public private(set) var content: OwnProfile?
    /// A refresh failed while content is on screen.
    public private(set) var refreshError: WaiveraError?
    public private(set) var isRefreshing = false
    public private(set) var celebration: Celebration?

    @ObservationIgnored private let session: any SessionRepository
    @ObservationIgnored private let profiles: any ProfileRepository
    @ObservationIgnored private let calendar: any CalendarRepository
    @ObservationIgnored private let realtime: any RealtimeStatusRepository
    @ObservationIgnored private var resource = Resource<OwnProfile>()
    @ObservationIgnored private var milestones = MilestoneIndex.empty
    @ObservationIgnored private var refreshInFlight = false

    public init(
        session: any SessionRepository,
        profiles: any ProfileRepository,
        calendar: any CalendarRepository,
        realtime: any RealtimeStatusRepository
    ) {
        self.session = session
        self.profiles = profiles
        self.calendar = calendar
        self.realtime = realtime
        let user = session.currentState.user
        self.user = user
        phase = user == nil ? .unavailable : .loading
    }

    public convenience init(environment: DataEnvironment) {
        self.init(
            session: environment.session,
            profiles: environment.profile,
            calendar: environment.calendar,
            realtime: environment.realtimeStatus
        )
    }

    /// The profile's saved zone, else the session's; dates and the Time zone row use it.
    public var timeZone: TimeZone { ProfileText.timeZone(profile: content?.profile, user: user).zone }

    public var displayName: String? { ProfileText.displayName(profile: content?.profile, user: user) }

    /// Observes the repositories until the calling task is cancelled (the view's `.task`).
    public func run() async {
        async let sessions: Void = observeSession()
        async let profile: Void = observeProfile()
        async let milestones: Void = observeMilestones()
        async let reconnects: Void = onReconnect(realtime) { await self.refresh() }
        await refresh()
        _ = await (sessions, profile, milestones, reconnects)
    }

    private func observeSession() async {
        for await state in session.states() { apply(user: state.user) }
    }

    private func observeProfile() async {
        for await value in profiles.profile() { apply(value) }
    }

    private func observeMilestones() async {
        var requested = false
        for await index in calendar.milestones() {
            apply(milestones: index.value ?? .empty)
            // Today and Schedule usually loaded them already; fetch only when nobody has.
            if !requested, index.value == nil, index.phase == .idle {
                requested = true
                await calendar.refreshMilestones()
            }
        }
    }

    /// Header Refresh and Retry. Ignored while a refresh runs or without a backend id.
    public func refresh() async {
        guard user != nil, !refreshInFlight else { return }
        refreshInFlight = true
        isRefreshing = true
        refreshError = nil
        await profiles.refresh()
        refreshInFlight = false
        isRefreshing = false
        derive()
    }

    /// A section card's Retry: refetches only that section.
    public func retry(section: ProfileSection) async {
        guard user != nil else { return }
        await profiles.refresh(section: section)
    }

    private func apply(user: CurrentUser?) {
        guard user != self.user else { return }
        self.user = user
        derive()
    }

    private func apply(_ value: Resource<OwnProfile>) {
        resource = value
        derive()
    }

    private func apply(milestones index: MilestoneIndex) {
        milestones = index
        updateCelebration()
    }

    private func derive() {
        content = resource.value
        guard user != nil else {
            phase = .unavailable
            celebration = nil
            return
        }
        if resource.value != nil {
            phase = .loaded
            refreshError = resource.error
        } else if let error = resource.error {
            phase = .failed(error)
            refreshError = nil
        } else {
            phase = .loading
        }
        updateCelebration()
    }

    private func updateCelebration() {
        guard let user else {
            celebration = nil
            return
        }
        celebration = milestones.celebration(for: user.id, on: calendar.today())
    }
}
