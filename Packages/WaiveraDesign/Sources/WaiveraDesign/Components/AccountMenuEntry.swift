#if canImport(UIKit)
    import SwiftUI

    /// The signed-in person's avatar in a hero bar and what tapping it does (Android
    /// `LocalSignedInAccount`). The app shell provides it once above the tabs, so every tab's
    /// `HeroTopBar` shows the avatar and opens the account menu without the screen knowing who is
    /// signed in or how the menu is presented.
    public struct AccountMenuEntry {
        public let name: String
        public let image: Image?
        public let openMenu: () -> Void

        public init(name: String, image: Image? = nil, openMenu: @escaping () -> Void) {
            self.name = name
            self.image = image
            self.openMenu = openMenu
        }
    }

    private struct AccountMenuEntryKey: EnvironmentKey {
        static var defaultValue: AccountMenuEntry? { nil }
    }

    public extension EnvironmentValues {
        /// Read by `HeroTopBar` when it is not given an account of its own.
        var waiveraAccountMenu: AccountMenuEntry? {
            get { self[AccountMenuEntryKey.self] }
            set { self[AccountMenuEntryKey.self] = newValue }
        }
    }
#endif
