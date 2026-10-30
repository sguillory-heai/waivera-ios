#if canImport(UIKit)
    import SwiftUI

    private struct EndlessMotionDisabledKey: EnvironmentKey {
        static let defaultValue = false
    }

    public extension EnvironmentValues {
        /// Stills the animations that never end on their own (the skeleton pulse, the busy ring).
        /// The app sets it for UI tests (`-WaiveraDisableAnimations`): XCUITest waits for the app
        /// to go idle before every query, screenshot and audit, and a looping SwiftUI animation
        /// keeps it busy until that wait times out. `UIView.setAnimationsEnabled(false)` does not
        /// reach SwiftUI animations.
        var waiveraEndlessMotionDisabled: Bool {
            get { self[EndlessMotionDisabledKey.self] }
            set { self[EndlessMotionDisabledKey.self] = newValue }
        }
    }
#endif
