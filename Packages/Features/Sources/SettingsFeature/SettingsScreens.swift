import SwiftUI
import WaiveraDesign

/// Settings root: Notifications, Appearance, Account.
public struct SettingsView: View {
    let onOpenNotifications: () -> Void
    let onOpenAppearance: () -> Void
    let onOpenAccount: () -> Void

    public init(
        onOpenNotifications: @escaping () -> Void,
        onOpenAppearance: @escaping () -> Void,
        onOpenAccount: @escaping () -> Void
    ) {
        self.onOpenNotifications = onOpenNotifications
        self.onOpenAppearance = onOpenAppearance
        self.onOpenAccount = onOpenAccount
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "settings.title", bundle: .module),
            systemImage: "gearshape"
        )
    }
}

/// System / Light / Dark, and the Haptics switch.
public struct AppearanceSettingsView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "settings.appearance.title", bundle: .module),
            systemImage: "circle.lefthalf.filled"
        )
    }
}

#Preview("Light") { NavigationStack { SettingsView(onOpenNotifications: {}, onOpenAppearance: {}, onOpenAccount: {}) } }
#Preview("Dark") { NavigationStack { AppearanceSettingsView() }.preferredColorScheme(.dark) }
#Preview("AX XXXL") {
    NavigationStack { SettingsView(onOpenNotifications: {}, onOpenAppearance: {}, onOpenAccount: {}) }.dynamicTypeSize(
        .accessibility5
    )
}
