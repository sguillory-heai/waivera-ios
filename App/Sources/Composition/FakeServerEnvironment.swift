#if DEBUG
    import Foundation
    import WaiveraNotifications

    /// The `-WaiveraFakeServer` environment. The shell gateways are fixed so the screenshot tour is
    /// deterministic: signed in as the fixture user, hub connected, permission already granted
    /// (no system prompt in UI tests). Feature data comes from the fake server in
    /// `WaiveraTestSupport` once `DataLayerBridge.makeFakeEnvironment` is wired (see app-shell.md).
    enum FakeServerEnvironment {
        /// Fixture user (spec/fixtures `rest-auth-login.json`).
        static let user = ShellUser(id: "usr_alex_rivera", displayName: "Alex Rivera")

        static func make() -> AppEnvironment {
            #if canImport(WaiveraTestSupport) && canImport(WaiveraData)
                if let environment = DataLayerBridge.makeFakeEnvironment() {
                    return environment
                }
            #endif
            return AppEnvironment(
                session: StaticSessionGateway(.signedIn(user)),
                preferences: StaticPreferencesGateway(),
                hub: StaticHubStatus(isConnected: true),
                chatActions: NoChatActions(),
                registerPush: { _ in },
                unregisterPush: {},
                tokenSource: SilentTokenSource(),
                authorizer: StaticAuthorizer(status: .authorized),
                // A throwaway suite so fake runs never mark the real primer as seen.
                primerStore: PrimerSeenStore(suiteName: "waivera.fake-server")
            )
        }
    }
#endif
