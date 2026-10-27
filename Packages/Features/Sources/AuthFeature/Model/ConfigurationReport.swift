import Foundation
import WaiveraAPI

/// What the configuration-missing gate can say about the build. Key names are Info.plist setting
/// names, never values, so they are safe to show; they are listed only in DEBUG builds, where
/// they help whoever is setting the build up (01 §3 "missing configuration").
public struct ConfigurationReport: Equatable, Sendable {
    public var missingKeys: [String]

    public init(missingKeys: [String]) {
        self.missingKeys = missingKeys
    }

    public static func make(info: [String: Any]) -> ConfigurationReport {
        switch WaiveraConfiguration.load(from: info) {
        case .success:
            ConfigurationReport(missingKeys: [])
        case .failure(let missing):
            ConfigurationReport(missingKeys: missing.keys.map(\.rawValue))
        }
    }

    /// The report for the running app, empty in Release builds.
    public static var current: ConfigurationReport {
        #if DEBUG
            make(info: Bundle.main.infoDictionary ?? [:])
        #else
            ConfigurationReport(missingKeys: [])
        #endif
    }
}
