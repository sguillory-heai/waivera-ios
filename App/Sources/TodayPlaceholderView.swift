import SwiftUI
import WaiveraDesign

/// Stand-in first screen until the Today slice lands in Phase 1.
struct TodayPlaceholderView: View {
    var body: some View {
        VStack(spacing: Spacing.small) {
            Text("Waivera")
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.accent)
                .accessibilityIdentifier("today.title")
            Text("Your schedule and chats will appear here.")
                .font(.body)
                .foregroundStyle(Palette.onSurface)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface)
    }
}

#Preview("Light") {
    TodayPlaceholderView()
}

#Preview("Dark") {
    TodayPlaceholderView()
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TodayPlaceholderView()
        .dynamicTypeSize(.accessibility5)
}
