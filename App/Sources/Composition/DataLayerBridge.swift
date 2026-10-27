#if canImport(WaiveraData)
    import Foundation
    import WaiveraAPI
    import WaiveraData
    import WaiveraNotifications

    // Adapts the data layer (Packages/WaiveraData, owned by the core agent) to the shell gateways.
    // Compiled only once WaiveraData is added to project.yml. Written against the protocols assumed
    // before docs/architecture/data-layer.md existed; reconcile with that doc when integrating:
    //   SessionRepository: observable `state` of .loading / .signedOut / .passwordChangeRequired /
    //     .signedIn(user) with `user.id` (backend id) and `user.displayName`; `signOut() async`.
    //   PushRegistrationRepository: `register(token:preferences:) async throws`, `unregister() async throws`.
    //   SettingsRepository: theme, haptics enabled, in-app banners, sound, per-category push prefs.
    enum DataLayerBridge {
        static func makeLiveEnvironment(
            configuration: AppConfiguration,
            tokenSource: any PushTokenSource
        ) -> AppEnvironment? {
            guard case .success = WaiveraConfiguration.load(from: configuration.infoDictionary) else {
                return nil
            }
            // Integration point: build the live repositories from `WaiveraData` here and wrap them
            // in gateways (see the adapters below). Until then the unconfigured environment is used.
            return nil
        }

        #if DEBUG && canImport(WaiveraTestSupport)
            static func makeFakeEnvironment() -> AppEnvironment? {
                // Integration point: repositories over `WaiveraTestSupport`'s fake server and hub.
                nil
            }
        #endif
    }
#endif
