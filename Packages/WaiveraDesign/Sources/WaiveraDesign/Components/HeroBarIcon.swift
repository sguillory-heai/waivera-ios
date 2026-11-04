#if canImport(UIKit)
    import SwiftUI

    /// A hero bar action's icon. Every tab's bar draws its actions at one fixed size (the chat
    /// list's New chat plus), whatever font is around it, so switching tabs never changes the size.
    /// Shapes that fill more of Android's box (the bell) are drawn smaller so they read the same size.
    public struct HeroBarIcon: View {
        /// The bell drawing fills more of its box than the plus, so it is drawn at this share.
        static let bellScale: CGFloat = 0.8

        private let systemName: String

        public init(systemName: String) {
            self.systemName = systemName
        }

        public var body: some View {
            WaiveraIcon(systemName: systemName, pointSize: ControlSize.icon * Self.opticalScale(for: systemName))
                .fontWeight(.semibold)
        }

        static func opticalScale(for systemName: String) -> CGFloat {
            WaiveraIcons.asset(for: systemName) == WaiveraIcons.asset(for: "bell") ? bellScale : 1
        }
    }
#endif
