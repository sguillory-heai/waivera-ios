#if canImport(UIKit)
    import SwiftUI

    public extension View {
        /// A floating control's lift (Android `shadow(Level3)` on a pill, such as Jump to latest):
        /// a tight contact shadow under the edge plus a soft key shadow below. One soft layer at
        /// Android's alpha read as no shadow at all on a phone (Sheldon, 2026-11-04).
        func floatingShadow() -> some View {
            shadow(color: Palette.elevationContact, radius: Elevation.level1, x: 0, y: Elevation.level1)
                .shadow(
                    color: Palette.elevationShadow,
                    radius: Elevation.level3,
                    x: 0,
                    y: Elevation.level3 / 2 + Elevation.level1
                )
        }
    }
#endif
