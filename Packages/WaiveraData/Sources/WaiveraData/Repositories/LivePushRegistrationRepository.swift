import Foundation
import WaiveraAPI

/// Registers this install's FCM token with sprout_api (09 §5). Fixes the Expo gaps: the
/// fingerprint of the last successful registration is persisted, bursts of preference
/// changes are debounced into one call, failures retry with backoff, a rotated token
/// re-registers, and sign-out unregisters.
public actor LivePushRegistrationRepository: PushRegistrationRepository {
    public static let debounce: Duration = .milliseconds(400)
    static let maxAttempts = 6

    private let api: APIClient
    private let store: any KeyValueStore
    private let deviceIdentifiers: (any DeviceIdentifierStore)?
    private let clock: any WaiveraClock
    private var token: String?
    private var preferences = NotificationPreferences()
    /// The scheduled registration; its value is the final error, or `nil` when it registered,
    /// had nothing to send, or was superseded.
    private var pending: Task<WaiveraError?, Never>?
    private var generation = 0

    /// `deviceIdentifiers` is the Keychain on device (IF-13); without it the id stays in `store`.
    public init(
        api: APIClient,
        store: any KeyValueStore,
        clock: any WaiveraClock,
        deviceIdentifiers: (any DeviceIdentifierStore)? = nil
    ) {
        self.api = api
        self.store = store
        self.clock = clock
        self.deviceIdentifiers = deviceIdentifiers
    }

    /// `waivera-<epoch ms>-<random>`, created once per device and kept across reinstalls when a
    /// Keychain store is given (push.md §1). An id an earlier build kept in `UserDefaults` moves
    /// to the Keychain once.
    public var deviceId: String {
        let legacy = store.value(String.self, forKey: StorageKey.pushInstallationId)
        guard let deviceIdentifiers else {
            if let legacy { return legacy }
            let created = makeDeviceId()
            store.setValue(created, forKey: StorageKey.pushInstallationId)
            return created
        }
        if let existing = deviceIdentifiers.load() {
            if legacy != nil { store.set(nil, forKey: StorageKey.pushInstallationId) }
            return existing
        }
        let identifier = legacy ?? makeDeviceId()
        deviceIdentifiers.save(identifier)
        // Until the Keychain has it (it can be locked), the defaults copy keeps the id stable.
        if deviceIdentifiers.load() == identifier {
            if legacy != nil { store.set(nil, forKey: StorageKey.pushInstallationId) }
        } else if legacy == nil {
            store.setValue(identifier, forKey: StorageKey.pushInstallationId)
        }
        return identifier
    }

    private func makeDeviceId() -> String {
        let millis = Int64(clock.now.timeIntervalSince1970 * 1_000)
        let random = String(UInt64.random(in: 0...UInt64(UInt32.max)), radix: 36)
        return "waivera-\(millis)-\(random)"
    }

    public func register(token: String, preferences: NotificationPreferences) async {
        self.token = token
        self.preferences = preferences
        schedule()
    }

    /// Registers and waits for the outcome, throwing the final error once the retries are
    /// spent, so `PushRegistrationCoordinator` really reaches `.failed` and retries on the next
    /// activation (IF-06). A newer registration that supersedes this one is not an error.
    public func registerAndWait(token: String, preferences: NotificationPreferences) async throws {
        await register(token: token, preferences: preferences)
        if let failure = await pending?.value { throw failure }
    }

    /// The FCM token rotated: re-register with the same preferences, without touching the hub.
    public func tokenDidChange(_ token: String) async {
        guard token != self.token else { return }
        self.token = token
        schedule()
    }

    public func preferencesDidChange(_ preferences: NotificationPreferences) async {
        guard preferences != self.preferences else { return }
        self.preferences = preferences
        guard token != nil else { return }
        schedule()
    }

    public func unregister() async {
        generation += 1
        pending?.cancel()
        pending = nil
        store.set(nil, forKey: StorageKey.pushFingerprint)
        try? await api.unregisterFromPush(deviceID: deviceId)
    }

    /// Sign-out: unregister and forget the token so a later sign-in must provide it again.
    public func reset() async {
        await unregister()
        token = nil
        preferences = NotificationPreferences()
    }

    /// Waits for a scheduled registration (tests).
    public func settle() async {
        _ = await pending?.value
    }

    private func schedule() {
        generation += 1
        pending?.cancel()
        let current = generation
        let clock = clock
        pending = Task {
            try? await clock.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return nil }
            return await self.sync(generation: current)
        }
    }

    /// Returns the error that ended the retries, or `nil`.
    private func sync(generation current: Int) async -> WaiveraError? {
        guard let token else { return nil }
        if !preferences.pushEnabled {
            store.set(nil, forKey: StorageKey.pushFingerprint)
            try? await api.unregisterFromPush(deviceID: deviceId)
            return nil
        }
        let request = MobilePushRegistrationRequest(
            deviceID: deviceId,
            pushToken: token,
            pushEnabled: preferences.pushEnabled,
            chatMessagesEnabled: preferences.chatMessages,
            mentionsEnabled: preferences.mentions,
            reactionsEnabled: preferences.reactions,
            activeCallsEnabled: preferences.activeCalls,
            soundEnabled: preferences.sound,
            vibrationEnabled: preferences.vibration,
            previewContentEnabled: preferences.previewContent
        )
        let fingerprint = Self.fingerprint(request)
        // Re-registering resets `lastRegisteredAt` and can drop an in-flight push (G-08).
        guard store.value(String.self, forKey: StorageKey.pushFingerprint) != fingerprint else { return nil }
        var failure = WaiveraError.invalidResponse
        for attempt in 1...Self.maxAttempts {
            guard generation == current, !Task.isCancelled else { return nil }
            do {
                try await api.registerForPush(request)
                store.setValue(fingerprint, forKey: StorageKey.pushFingerprint)
                return nil
            } catch {
                failure = WaiveraError.from(error)
                guard failure.isTransient, attempt < Self.maxAttempts else { break }
                try? await clock.sleep(for: .seconds(min(60, 1 << attempt)))
            }
        }
        // Nothing is stored, so the next activation or token change tries again.
        return generation == current ? failure : nil
    }

    /// A digest of the request, so the device store never holds the push token itself.
    /// FNV-1a is enough here: it only detects change, it does not protect anything.
    static func fingerprint(_ request: MobilePushRegistrationRequest) -> String {
        guard let data = try? WaiveraJSON.encoder().encode(request) else { return "" }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
