#if canImport(UIKit)
    import SwiftUI

    public extension View {
        /// For a screen whose `HeroSection` runs up under a visible navigation bar (Profile,
        /// Person). Apply it to the content that draws the hero, not to an error state without one.
        ///
        /// Bar items are light for the plum. At rest the bar has no background, so the hero shows
        /// through; once content scrolls under it, the bar takes the hero's top colour, so the light
        /// title never sits on page-coloured cards. From iOS 26 the scroll edge effect is off: it
        /// washed the top of the hero to the page colour and left the light title and buttons on a
        /// pale band (CI run 41395581871, light mode).
        func heroUnderNavigationBar() -> some View {
            modifier(HeroUnderNavigationBar())
        }
    }

    private struct HeroUnderNavigationBar: ViewModifier {
        func body(content: Content) -> some View {
            let bar =
                content
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(HeroPalette.headerTop, for: .navigationBar)
                .toolbarBackground(.automatic, for: .navigationBar)
            if #available(iOS 26, *) {
                bar.scrollEdgeEffectHidden(true, for: .top)
            } else {
                bar
            }
        }
    }
#endif
