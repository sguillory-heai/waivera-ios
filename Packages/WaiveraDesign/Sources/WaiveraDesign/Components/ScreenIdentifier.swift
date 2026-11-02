#if canImport(UIKit)
    import SwiftUI

    public extension View {
        /// Names a whole screen for UI tests (`screen.<route>`). An identifier set on a plain
        /// container is handed down to its controls and replaces their own (CI run 41381753860:
        /// the password-change Save button answered to the screen's name), so the screen becomes
        /// one containing element that carries the name while its controls keep theirs.
        func screenIdentifier(_ identifier: String) -> some View {
            accessibilityElement(children: .contain)
                .accessibilityIdentifier(identifier)
        }
    }
#endif
