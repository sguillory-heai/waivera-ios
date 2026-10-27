import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraDataPersistence
import WaiveraRealtimeSignalR

#if DEBUG
    import WaiveraTestSupport
#endif

/// Builds the data layer (docs/architecture/data-layer.md, "Live composition").
enum DataLayerBridge {
    /// `nil` when the build has no API base URL or Firebase key.
    static func makeLiveEnvironment(configuration: AppConfiguration) -> DataEnvironment? {
        guard case .success(let apiConfiguration) = WaiveraConfiguration.load(from: configuration.infoDictionary)
        else { return nil }
        let localStore: any LocalStore
        if let store = try? SwiftDataLocalStore.make() {
            localStore = store
        } else {
            // The cache only speeds up the first frame; the app works without it.
            localStore = InMemoryLocalStore()
        }
        let tokenStore = KeychainTokenStore()
        let keyValueStore = UserDefaultsKeyValueStore()
        // Before anything reads the session: a reinstall never signs the previous person in (IS-01).
        FirstLaunchGuard.run(defaults: keyValueStore, tokenStore: tokenStore)
        return DataEnvironment.live(
            LiveDependencies(
                configuration: apiConfiguration,
                tokenStore: tokenStore,
                hubFactory: SignalRHubConnectionFactory(),
                localStore: localStore,
                keyValueStore: keyValueStore,
                connectivity: NetworkPathConnectivity(),
                deviceIdentifiers: KeychainDeviceIdentifierStore()
            )
        )
    }

    #if DEBUG
        /// The fixture-backed repositories and scripted hub for `-WaiveraFakeServer`.
        static func makeFakeEnvironment(_ scenario: FakeDataEnvironment.Scenario, webBaseURL: URL?) -> DataEnvironment {
            FakeDataEnvironment.make(scenario, webBaseURL: webBaseURL).environment
        }
    #endif
}
