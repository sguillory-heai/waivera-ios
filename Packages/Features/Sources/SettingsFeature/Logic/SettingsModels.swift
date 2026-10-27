import Foundation
import Observation
import WaiveraAPI
import WaiveraData
import WaiveraNotifications

/// Settings → Notifications (08 §8).
///
/// These are server preferences: the data layer sends the full set with every registration
/// (gap G-08), unregisters once when push turns off and registers once when it turns back on.
/// While push is off the other switches are dimmed and their stored values are kept, so turning
/// push back on restores them. In-app banners and in-app sound are applied on the device by the
/// foreground presentation rule. Alert sounds, banner style and lock screen previews per
/// category belong to iOS, which the screen links to.
@MainActor
@Observable
public final class NotificationSettingsModel {
    public private(set) var preferences: NotificationPreferences
    public private(set) var isLoaded = false

    /// One switch change, for bindings that cannot await.
    public enum Change: Equatable, Sendable {
        case push(Bool)
        case meaning(NotificationMeaning, Bool)
        case previews(Bool)
        case inAppBanners(Bool)
        case inAppSound(Bool)
    }

    @ObservationIgnored private let settings: any SettingsRepository
    @ObservationIgnored private let writes = WriteQueue()

    public init(settings: any SettingsRepository) {
        self.settings = settings
        preferences = settings.currentSettings.notifications
    }

    /// Applies a change from a switch binding. Writes run in order; the switch flips at once.
    public func apply(_ change: Change) {
        writes.enqueue { await self.perform(change) }
    }

    /// Waits for every change applied so far to reach the settings store.
    public func waitForWrites() async {
        await writes.drain()
    }

    private func perform(_ change: Change) async {
        switch change {
        case .push(let isOn): await setPushEnabled(isOn)
        case .meaning(let meaning, let isOn): await set(meaning, isOn: isOn)
        case .previews(let isOn): await setPreviewContent(isOn)
        case .inAppBanners(let isOn): await setInAppBanners(isOn)
        case .inAppSound(let isOn): await setInAppSound(isOn)
        }
    }

    public convenience init(environment: DataEnvironment) {
        self.init(settings: environment.settings)
    }

    /// Category, preview and in-app switches are disabled, not changed, while push is off.
    public var categoriesEnabled: Bool { preferences.pushEnabled }

    public func isOn(_ meaning: NotificationMeaning) -> Bool {
        NotificationSwitches.isOn(meaning, in: preferences)
    }

    public func run() async {
        for await value in settings.settings() {
            preferences = value.notifications
            isLoaded = true
        }
    }

    public func setPushEnabled(_ isOn: Bool) async {
        guard isOn != preferences.pushEnabled else { return }
        preferences.pushEnabled = isOn
        await settings.update { $0.notifications.pushEnabled = isOn }
    }

    public func set(_ meaning: NotificationMeaning, isOn: Bool) async {
        guard categoriesEnabled, NotificationSwitches.isSupported(meaning), self.isOn(meaning) != isOn else { return }
        NotificationSwitches.set(meaning, to: isOn, in: &preferences)
        await settings.update { NotificationSwitches.set(meaning, to: isOn, in: &$0.notifications) }
    }

    public func setPreviewContent(_ isOn: Bool) async {
        await setFlag(\.previewContent, isOn)
    }

    public func setInAppBanners(_ isOn: Bool) async {
        await setFlag(\.inAppBanners, isOn)
    }

    public func setInAppSound(_ isOn: Bool) async {
        await setFlag(\.sound, isOn)
    }

    private func setFlag(_ flag: WritableKeyPath<NotificationPreferences, Bool> & Sendable, _ isOn: Bool) async {
        guard categoriesEnabled, preferences[keyPath: flag] != isOn else { return }
        preferences[keyPath: flag] = isOn
        await settings.update { $0.notifications[keyPath: flag] = isOn }
    }
}

/// Settings → Appearance: theme and the haptics switch. The app root reads the same settings
/// stream, so a change applies at once and System follows the device as it switches.
@MainActor
@Observable
public final class AppearanceModel {
    public private(set) var appearance: AppearancePreference
    public private(set) var hapticsEnabled: Bool

    @ObservationIgnored private let settings: any SettingsRepository
    @ObservationIgnored private let writes = WriteQueue()

    public init(settings: any SettingsRepository) {
        self.settings = settings
        appearance = settings.currentSettings.appearance
        hapticsEnabled = settings.currentSettings.hapticsEnabled
    }

    /// For taps and switch bindings that cannot await. Writes run in order.
    public func choose(_ preference: AppearancePreference) {
        writes.enqueue { await self.select(preference) }
    }

    public func toggleHaptics(_ isOn: Bool) {
        writes.enqueue { await self.setHapticsEnabled(isOn) }
    }

    public func waitForWrites() async {
        await writes.drain()
    }

    public convenience init(environment: DataEnvironment) {
        self.init(settings: environment.settings)
    }

    public func run() async {
        for await value in settings.settings() {
            appearance = value.appearance
            hapticsEnabled = value.hapticsEnabled
        }
    }

    public func select(_ preference: AppearancePreference) async {
        guard preference != appearance else { return }
        appearance = preference
        await settings.update { $0.appearance = preference }
    }

    public func setHapticsEnabled(_ isOn: Bool) async {
        guard isOn != hapticsEnabled else { return }
        hapticsEnabled = isOn
        await settings.update { $0.hapticsEnabled = isOn }
    }
}

/// The signed-in identity as Settings shows it.
public struct AccountSummary: Equatable, Sendable {
    public var name: String?
    public var email: String?
    public var organization: String?

    public init(user: CurrentUser) {
        let chatName = user.asChatUser.fullName
        name = chatName == user.email ? nil : chatName
        email = user.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        organization = user.organization?.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

/// Settings index and Account: the identity summary and sign-out.
///
/// Sign-out itself is `SessionRepository.signOut()` (through the router's `onSignOut`), which
/// unregisters the push token, stops realtime, clears caches and signs out of Firebase. This
/// model only confirms first and makes a second tap a no-op.
@MainActor
@Observable
public final class AccountModel {
    public private(set) var account: AccountSummary?
    public var isConfirmingSignOut = false
    public private(set) var isSigningOut = false

    @ObservationIgnored private let session: any SessionRepository

    public init(session: any SessionRepository) {
        self.session = session
        account = session.currentState.user.map(AccountSummary.init)
    }

    public convenience init(environment: DataEnvironment) {
        self.init(session: environment.session)
    }

    public func run() async {
        for await state in session.states() {
            account = state.user.map(AccountSummary.init)
            if case .signedOut = state { isConfirmingSignOut = false }
        }
    }

    public func requestSignOut() {
        guard !isSigningOut, account != nil else { return }
        isConfirmingSignOut = true
    }

    /// `true` exactly once: the caller then signs out. Later calls return `false`.
    public func confirmSignOut() -> Bool {
        guard !isSigningOut, account != nil else { return false }
        isSigningOut = true
        isConfirmingSignOut = false
        return true
    }
}

/// Runs settings writes one after another. The model owns the chain; a write is short and must
/// finish even when the screen goes away, so nothing cancels it.
@MainActor
final class WriteQueue {
    private var tail: Task<Void, Never>?

    func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    func drain() async {
        await tail?.value
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
