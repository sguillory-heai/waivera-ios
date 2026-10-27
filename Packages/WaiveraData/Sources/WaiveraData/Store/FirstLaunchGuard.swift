import Foundation
import WaiveraAPI

/// Keychain items outlive an app delete, but `UserDefaults` does not. On the first launch after
/// an install (no marker in defaults) the stored auth session is removed, so deleting and
/// reinstalling the app, a common way to "reset" a shared device, never signs the previous
/// person back in (IS-01). The push device id is a separate Keychain item and is kept, so the
/// server can still replace this device's old registration (IF-13).
///
/// Run it before the token provider reads the store.
public enum FirstLaunchGuard {
    /// Returns `true` when this was the first launch and the session was removed.
    @discardableResult
    public static func run(defaults: any KeyValueStore, tokenStore: any TokenStore) -> Bool {
        guard defaults.data(forKey: StorageKey.installMarker) == nil else { return false }
        do {
            try tokenStore.clear()
        } catch {
            // Left unmarked, so the next launch tries again before reading the session.
            return false
        }
        defaults.setValue(true, forKey: StorageKey.installMarker)
        return true
    }
}
