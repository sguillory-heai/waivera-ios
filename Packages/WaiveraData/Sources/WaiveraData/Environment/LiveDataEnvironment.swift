import Foundation
import WaiveraAPI
import WaiveraRealtime

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// What the app target supplies to build the live environment.
public struct LiveDependencies: Sendable {
    public var configuration: WaiveraConfiguration
    public var tokenStore: any TokenStore
    public var hubFactory: any HubConnectionFactory
    public var localStore: any LocalStore
    public var keyValueStore: any KeyValueStore
    public var connectivity: any ConnectivityMonitor
    public var transport: any HTTPTransport
    public var clock: any WaiveraClock
    /// The push `deviceId` store (the Keychain on device, IF-13).
    public var deviceIdentifiers: (any DeviceIdentifierStore)?

    public init(
        configuration: WaiveraConfiguration,
        tokenStore: any TokenStore,
        hubFactory: any HubConnectionFactory,
        localStore: any LocalStore,
        keyValueStore: any KeyValueStore,
        connectivity: any ConnectivityMonitor,
        transport: any HTTPTransport = URLSession.shared,
        clock: any WaiveraClock = SystemClock(),
        deviceIdentifiers: (any DeviceIdentifierStore)? = nil
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.hubFactory = hubFactory
        self.localStore = localStore
        self.keyValueStore = keyValueStore
        self.connectivity = connectivity
        self.transport = transport
        self.clock = clock
        self.deviceIdentifiers = deviceIdentifiers
    }
}

extension DataEnvironment {
    public static func live(_ dependencies: LiveDependencies) -> DataEnvironment {
        let clock = dependencies.clock
        let auth = FirebaseTokenProvider(
            auth: FirebaseAuthREST(
                apiKey: dependencies.configuration.firebaseAPIKey,
                bundleIdentifier: dependencies.configuration.bundleIdentifier,
                transport: dependencies.transport,
                clock: clock
            ),
            store: dependencies.tokenStore,
            clock: clock
        )
        let api = APIClient(
            baseURL: dependencies.configuration.apiBaseURL,
            transport: dependencies.transport,
            tokens: auth
        )
        let realtime = LiveRealtimeClient(
            hubURL: dependencies.configuration.chatHubURL,
            factory: dependencies.hubFactory,
            tokens: auth,
            clock: clock
        )
        return assemble(
            auth: auth,
            api: api,
            realtime: realtime,
            webBaseURL: dependencies.configuration.webBaseURL,
            localStore: dependencies.localStore,
            keyValueStore: dependencies.keyValueStore,
            connectivity: dependencies.connectivity,
            clock: clock,
            deviceIdentifiers: dependencies.deviceIdentifiers
        )
    }

    /// Wires live repositories over any auth, API transport and hub. Also used by tests and by
    /// the fake server, which pass fixture-backed transports.
    public static func assemble(
        auth: any AuthSession,
        api: APIClient,
        realtime: any RealtimeClient,
        webBaseURL: URL?,
        localStore: any LocalStore,
        keyValueStore: any KeyValueStore,
        connectivity: any ConnectivityMonitor,
        clock: any WaiveraClock,
        deviceIdentifiers: (any DeviceIdentifierStore)? = nil
    ) -> DataEnvironment {
        let context = SessionContext()
        let presence = ChatPresence()
        let settings = LiveSettingsRepository(store: keyValueStore)
        let chat = ChatEngine(
            api: api,
            realtime: realtime,
            store: localStore,
            clock: clock,
            presence: presence,
            alertPreferences: { settings.currentSettings.notifications }
        )
        let handoff = WebCallHandoff(webBaseURL: webBaseURL, api: api)
        let activity = LiveActivityRepository(api: api, store: localStore, clock: clock)
        let bookmarks = LiveBookmarksRepository(api: api, context: context, chat: chat, clock: clock)
        let people = LivePeopleRepository(api: api, store: localStore, clock: clock)
        let profile = LiveProfileRepository(api: api, context: context, store: localStore, clock: clock)
        let calendar = LiveCalendarRepository(
            api: api,
            context: context,
            store: localStore,
            clock: clock,
            handoff: handoff
        )
        let push = LivePushRegistrationRepository(
            api: api,
            store: keyValueStore,
            clock: clock,
            deviceIdentifiers: deviceIdentifiers
        )
        let attachments = LiveAttachmentsRepository(api: api)
        let avatars = LiveAvatarRepository(api: api, clock: clock)
        let ingestor = RealtimeIngestor(
            realtime: realtime,
            chat: chat,
            activity: activity,
            bookmarks: bookmarks,
            calendar: calendar
        )
        let session = LiveSessionRepository(
            auth: auth,
            api: api,
            context: context,
            localStore: localStore,
            clock: clock
        )
        let coordinator = SessionCoordinator(
            chat: chat,
            realtime: realtime,
            ingestor: ingestor,
            activity: activity,
            bookmarks: bookmarks,
            people: people,
            profile: profile,
            calendar: calendar,
            push: push,
            attachments: attachments,
            avatars: avatars,
            localStore: localStore,
            keyValueStore: keyValueStore,
            connectivity: connectivity,
            settings: settings,
            context: context,
            clock: clock
        )
        return DataEnvironment(
            session: session,
            conversations: chat,
            messages: chat,
            threads: chat,
            attachments: attachments,
            avatars: avatars,
            bookmarks: bookmarks,
            activity: activity,
            people: people,
            calendar: calendar,
            profile: profile,
            settings: settings,
            push: push,
            realtimeStatus: LiveRealtimeStatusRepository(realtime: realtime, connectivity: connectivity),
            alerts: LiveChatAlertsRepository(chat: chat, presence: presence, realtime: realtime),
            clock: clock,
            callURL: { try await handoff.url(for: $0) },
            foreground: { isForeground in
                if isForeground { await auth.reloadStoredSession() }
                await chat.foregroundChanged(isForeground)
                await realtime.setForeground(isForeground)
            },
            start: {
                await session.setParticipants([coordinator])
                await coordinator.observeDevice()
                await session.start()
            },
            protectedDataAvailable: { await auth.reloadStoredSession() }
        )
    }
}

/// Starts every session-scoped piece in order, and tears them down in the reverse order
/// sign-out needs: push unregister and realtime stop while still authenticated, then caches.
actor SessionCoordinator: SessionLifecycleParticipant {
    let chat: ChatEngine
    let realtime: any RealtimeClient
    let ingestor: RealtimeIngestor
    let activity: LiveActivityRepository
    let bookmarks: LiveBookmarksRepository
    let people: LivePeopleRepository
    let profile: LiveProfileRepository
    let calendar: LiveCalendarRepository
    let push: LivePushRegistrationRepository
    let attachments: LiveAttachmentsRepository
    let avatars: LiveAvatarRepository
    let localStore: any LocalStore
    let keyValueStore: any KeyValueStore
    let connectivity: any ConnectivityMonitor
    let settings: LiveSettingsRepository
    let context: SessionContext
    let clock: any WaiveraClock
    private var deviceTasks: [Task<Void, Never>] = []

    init(
        chat: ChatEngine,
        realtime: any RealtimeClient,
        ingestor: RealtimeIngestor,
        activity: LiveActivityRepository,
        bookmarks: LiveBookmarksRepository,
        people: LivePeopleRepository,
        profile: LiveProfileRepository,
        calendar: LiveCalendarRepository,
        push: LivePushRegistrationRepository,
        attachments: LiveAttachmentsRepository,
        avatars: LiveAvatarRepository,
        localStore: any LocalStore,
        keyValueStore: any KeyValueStore,
        connectivity: any ConnectivityMonitor,
        settings: LiveSettingsRepository,
        context: SessionContext,
        clock: any WaiveraClock
    ) {
        self.chat = chat
        self.realtime = realtime
        self.ingestor = ingestor
        self.activity = activity
        self.bookmarks = bookmarks
        self.people = people
        self.profile = profile
        self.calendar = calendar
        self.push = push
        self.attachments = attachments
        self.avatars = avatars
        self.localStore = localStore
        self.keyValueStore = keyValueStore
        self.connectivity = connectivity
        self.settings = settings
        self.context = context
        self.clock = clock
    }

    /// Network changes gate realtime and resume queued sends; notification switches
    /// re-register push (debounced in the push repository).
    func observeDevice() {
        guard deviceTasks.isEmpty else { return }
        let online = connectivity.isOnline()
        let settingsStream = settings.settings()
        deviceTasks = [
            Task { [realtime, chat] in
                for await isOnline in online {
                    await realtime.setNetworkAvailable(isOnline)
                    if isOnline { await chat.resumeOutbox() }
                }
            },
            Task { [push] in
                for await value in settingsStream { await push.preferencesDidChange(value.notifications) }
            },
        ]
    }

    func sessionDidStart(_ user: CurrentUser) async {
        // Belt and braces for AF-04 / AS-01: a cache written for anyone else is never shown.
        let owner = keyValueStore.value(String.self, forKey: StorageKey.cacheOwner)
        if let owner, owner != user.id { await localStore.removeAll() }
        var since = keyValueStore.value(Date.self, forKey: StorageKey.accountSince)
        if owner != user.id || since == nil {
            since = clock.now
            keyValueStore.setValue(since, forKey: StorageKey.accountSince)
        }
        context.setAccountSince(since)
        keyValueStore.setValue(user.id, forKey: StorageKey.cacheOwner)
        await chat.begin(user: user)
        await activity.begin()
        await people.begin()
        await profile.begin()
        await calendar.begin()
        await ingestor.start()
        await realtime.start()
        Task { [chat, activity, calendar] in
            await chat.refresh()
            await activity.refresh()
            await calendar.refreshMilestones()
        }
    }

    func sessionWillEnd() async {
        await push.reset()
        await ingestor.stop()
        await realtime.stop()
    }

    func sessionDidEnd() async {
        await chat.end()
        await chat.flushPersistence()
        await activity.reset()
        await bookmarks.reset()
        await people.reset()
        await profile.reset()
        await calendar.reset()
        await attachments.clear()
        await avatars.clear()
        await localStore.removeAll()
        for key in StorageKey.personal { keyValueStore.set(nil, forKey: key) }
        context.setAccountSince(nil)
    }
}
