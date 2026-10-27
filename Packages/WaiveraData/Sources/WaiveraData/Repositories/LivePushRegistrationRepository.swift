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
    private let clock: any WaiveraClock
    private var token: String?
    private var preferences = NotificationPreferences()
    private var pending: Task<Void, Never>?
    private var generation = 0

    public init(api: APIClient, store: any KeyValueStore, clock: any WaiveraClock) {
        self.api = api
        self.store = store
        self.clock = clock
    }

    /// `waivera-<epoch ms>-<random>`, created once per install (09 §3).
    public var deviceId: String {
        if let existing = store.value(String.self, forKey: StorageKey.pushInstallationId) { return existing }
        let millis = Int64(clock.now.timeIntervalSince1970 * 1_000)
        let random = String(UInt64.random(in: 0...UInt64(UInt32.max)), radix: 36)
        let created = "waivera-\(millis)-\(random)"
        store.setValue(created, forKey: StorageKey.pushInstallationId)
        return created
    }

    public func register(token: String, preferences: NotificationPreferences) async {
        self.token = token
        self.preferences = preferences
        schedule()
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
        await pending?.value
    }

    private func schedule() {
        generation += 1
        pending?.cancel()
        let current = generation
        let clock = clock
        pending = Task {
            try? await clock.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self.sync(generation: current)
        }
    }

    private func sync(generation current: Int) async {
        guard let token else { return }
        if !preferences.pushEnabled {
            store.set(nil, forKey: StorageKey.pushFingerprint)
            try? await api.unregisterFromPush(deviceID: deviceId)
            return
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
        guard store.value(String.self, forKey: StorageKey.pushFingerprint) != fingerprint else { return }
        for attempt in 1...Self.maxAttempts {
            guard generation == current, !Task.isCancelled else { return }
            do {
                try await api.registerForPush(request)
                store.setValue(fingerprint, forKey: StorageKey.pushFingerprint)
                return
            } catch {
                guard WaiveraError.from(error).isTransient, attempt < Self.maxAttempts else { return }
                try? await clock.sleep(for: .seconds(min(60, 1 << attempt)))
            }
        }
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
