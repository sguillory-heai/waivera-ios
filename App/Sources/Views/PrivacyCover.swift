import SwiftUI
import WaiveraDesign

/// Covers the app while it is inactive or in the background, so the app switcher snapshot
/// shows no chat content. Purely visual: nothing below it is torn down.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(WaiveraFont.sectionTitle)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(AppStrings.privacyCover))
    }
}
