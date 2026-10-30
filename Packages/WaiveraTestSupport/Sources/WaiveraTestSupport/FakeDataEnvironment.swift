import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraRealtime

/// Every repository faked over `DemoData`, for previews, feature-model tests, UI tests and
/// the DEBUG-only `-WaiveraFakeServer` launch argument. Nothing touches the network.
public struct FakeDataEnvironment: Sendable {
    public enum Scenario: String, Sendable, CaseIterable {
        /// Signed in with the full demo data.
        case demo
        /// Signed in, every list empty.
        case empty
        /// Signed in, every load fails with a server error.
        case failing
        /// Every load takes 600 ms, to review skeletons.
        case slow
        /// The login screen; `FakeSessionRepository.password` signs in.
        case signedOut
        /// Signed in behind the forced password change.
        case passwordChange
    }

    /// Launch argument that selects the fake environment (DEBUG builds only).
    public static let launchArgument = "-WaiveraFakeServer"
    /// Optional launch argument followed by a `Scenario` raw value.
    public static let scenarioArgument = "-WaiveraFakeScenario"

    public let data: DemoData
    public let clock: any WaiveraClock
    public let realtime: FakeRealtimeClient
    public let session: FakeSessionRepository
    public let chat: FakeChatRepository
    public let attachments: FakeAttachmentsRepository
    public let bookmarks: FakeBookmarksRepository
    public let activity: FakeActivityRepository
    public let people: FakePeopleRepository
    public let calendar: FakeCalendarRepository
    public let profile: FakeProfileRepository
    public let settings: FakeSettingsRepository
    public let push: FakePushRegistrationRepository
    public let realtimeStatus: FakeRealtimeStatusRepository
    public let alerts: FakeChatAlertsRepository
    public let environment: DataEnvironment

    /// The scenario the launch arguments ask for, or `nil` when the fake was not requested.
    public static func scenario(fromArguments arguments: [String]) -> Scenario? {
        guard arguments.contains(launchArgument) else { return nil }
        guard let index = arguments.firstIndex(of: scenarioArgument), arguments.indices.contains(index + 1) else {
            return .demo
        }
        return Scenario(rawValue: arguments[index + 1]) ?? .demo
    }

    /// - Parameters:
    ///   - clock: `ManualClock` in tests; the default `DemoClock` runs in real time from
    ///     `DemoData.now`, so the app shows the demo "today".
    ///   - webBaseURL: where call and meeting links point; `nil` makes them throw
    ///     `.configurationMissing`.
    public static func make(
        _ scenario: Scenario = .demo,
        clock: any WaiveraClock = DemoClock(),
        connectsRealtimeOnStart: Bool = true,
        webBaseURL: URL? = nil
    ) -> FakeDataEnvironment {
        let data = scenario == .empty ? DemoData.empty : DemoData.make()
        let realtime = FakeRealtimeClient(clock: clock, connectsOnStart: connectsRealtimeOnStart)
        let presence = ChatPresence()
        let push = FakePushRegistrationRepository()
        let session = FakeSessionRepository(
            user: data.user,
            initial: scenario == .signedOut ? .signedOut(nil) : .loading,
            onSignOut: {
                await push.unregister()
                await realtime.stop()
            }
        )
        session.requiresPasswordChange.update { $0 = scenario == .passwordChange }
        let fakes = FakeDataEnvironment(
            data: data,
            clock: clock,
            realtime: realtime,
            session: session,
            chat: FakeChatRepository(data: data, clock: clock, presence: presence),
            attachments: FakeAttachmentsRepository(),
            bookmarks: FakeBookmarksRepository(data.bookmarks, clock: clock),
            activity: FakeActivityRepository(data.activity, clock: clock),
            people: FakePeopleRepository(directory: data.directory, people: data.people, clock: clock),
            calendar: FakeCalendarRepository(data: data, clock: clock, lobbyBase: webBaseURL),
            profile: FakeProfileRepository(data.profile, clock: clock),
            settings: FakeSettingsRepository(),
            push: push,
            realtimeStatus: FakeRealtimeStatusRepository(realtime: realtime),
            alerts: FakeChatAlertsRepository(presence: presence, realtime: realtime),
            webBaseURL: webBaseURL
        )
        switch scenario {
        case .failing: fakes.setControls(FakeControls(failure: .server(statusCode: 503)))
        case .slow: fakes.setControls(FakeControls(latency: .milliseconds(600)))
        default: break
        }
        return fakes
    }

    /// Applies the same failure or latency to every repository.
    public func setControls(_ controls: FakeControls) {
        chat.setInboxControls(controls)
        chat.setTimelineControls(controls)
        bookmarks.resource.setControls(controls)
        activity.resource.setControls(controls)
        people.resource.setControls(controls)
        profile.resource.setControls(controls)
        calendar.controls.update { $0 = controls }
        calendar.milestoneResource.setControls(controls)
    }

    private init(
        data: DemoData,
        clock: any WaiveraClock,
        realtime: FakeRealtimeClient,
        session: FakeSessionRepository,
        chat: FakeChatRepository,
        attachments: FakeAttachmentsRepository,
        bookmarks: FakeBookmarksRepository,
        activity: FakeActivityRepository,
        people: FakePeopleRepository,
        calendar: FakeCalendarRepository,
        profile: FakeProfileRepository,
        settings: FakeSettingsRepository,
        push: FakePushRegistrationRepository,
        realtimeStatus: FakeRealtimeStatusRepository,
        alerts: FakeChatAlertsRepository,
        webBaseURL: URL?
    ) {
        self.data = data
        self.clock = clock
        self.realtime = realtime
        self.session = session
        self.chat = chat
        self.attachments = attachments
        self.bookmarks = bookmarks
        self.activity = activity
        self.people = people
        self.calendar = calendar
        self.profile = profile
        self.settings = settings
        self.push = push
        self.realtimeStatus = realtimeStatus
        self.alerts = alerts
        environment = DataEnvironment(
            session: session,
            conversations: chat,
            messages: chat,
            threads: chat,
            attachments: attachments,
            avatars: FakeAvatarRepository(),
            bookmarks: bookmarks,
            activity: activity,
            people: people,
            calendar: calendar,
            profile: profile,
            settings: settings,
            push: push,
            realtimeStatus: realtimeStatus,
            alerts: alerts,
            clock: clock,
            callURL: { conversation in
                guard let webBaseURL else { throw WaiveraError.configurationMissing }
                return webBaseURL.appending(path: "lobby").appending(path: "demo-\(conversation.id)")
            },
            foreground: { [presence = chat.presence] isForeground in
                presence.setForeground(isForeground)
                await realtime.setForeground(isForeground)
            },
            start: {
                await session.start()
                await realtime.start()
            }
        )
    }
}

/// Real time, shifted so the app starts at `DemoData.now`.
public struct DemoClock: WaiveraClock {
    private let offset: TimeInterval

    public init(start: Date = DemoData.now) {
        offset = start.timeIntervalSinceNow
    }

    public var now: Date { Date().addingTimeInterval(offset) }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
