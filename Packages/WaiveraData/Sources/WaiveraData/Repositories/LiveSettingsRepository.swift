import Foundation
import WaiveraAPI

/// Settings in the device key-value store, read synchronously so the stored appearance
/// applies before the first frame (08 §7).
public final class LiveSettingsRepository: SettingsRepository {
    private let store: any KeyValueStore
    private let cell: StateCell<AppSettings>

    public init(store: any KeyValueStore) {
        self.store = store
        cell = StateCell(store.value(AppSettings.self, forKey: StorageKey.settings) ?? AppSettings())
    }

    public func settings() -> AsyncStream<AppSettings> { cell.stream() }
    public var currentSettings: AppSettings { cell.current }

    public func update(_ transform: @Sendable (inout AppSettings) -> Void) async {
        let next = cell.update(transform)
        store.setValue(next, forKey: StorageKey.settings)
    }
}
