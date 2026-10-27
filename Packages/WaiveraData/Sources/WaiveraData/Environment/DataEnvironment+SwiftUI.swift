#if canImport(SwiftUI)
    import SwiftUI

    private struct DataEnvironmentKey: EnvironmentKey {
        static let defaultValue: DataEnvironment? = nil
    }

    extension EnvironmentValues {
        /// The repositories for feature screens. The app root injects it once the composition root
        /// has built the live or fake environment; previews inject
        /// `FakeDataEnvironment.make().environment` from WaiveraTestSupport. `nil` only in a build
        /// without API configuration, where the app shows the configuration-missing gate and no
        /// feature screen.
        public var dataEnvironment: DataEnvironment? {
            get { self[DataEnvironmentKey.self] }
            set { self[DataEnvironmentKey.self] = newValue }
        }
    }
#endif
