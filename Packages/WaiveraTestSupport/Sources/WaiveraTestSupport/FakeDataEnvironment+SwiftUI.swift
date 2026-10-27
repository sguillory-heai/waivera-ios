#if canImport(SwiftUI)
    import SwiftUI
    import WaiveraData

    extension View {
        /// For previews: injects a launched fake data environment for `scenario`, so a screen
        /// renders demo, empty, failing or slow data without a network. Call it inside `#if DEBUG`.
        public func fakeDataEnvironment(_ scenario: FakeDataEnvironment.Scenario = .demo) -> some View {
            let environment = FakeDataEnvironment.make(scenario).environment
            return self.environment(\.dataEnvironment, environment)
                .task { await environment.launch() }
        }
    }
#endif
