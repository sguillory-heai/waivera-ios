import SwiftUI
import WaiveraDesign
import WaiveraNotifications

/// Settings → Notifications. Always shows the system permission state first: when notifications
/// are off at the system level it says so and links to the system Settings app (09-push §5).
/// The per-category switches are the settings agent's to add below the status card.
public struct NotificationSettingsView: View {
    let systemStatus: SystemNotificationStatus
    let onRequestPermission: () -> Void
    let onOpenSystemSettings: () -> Void

    public init(
        systemStatus: SystemNotificationStatus,
        onRequestPermission: @escaping () -> Void,
        onOpenSystemSettings: @escaping () -> Void
    ) {
        self.systemStatus = systemStatus
        self.onRequestPermission = onRequestPermission
        self.onOpenSystemSettings = onOpenSystemSettings
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.medium) {
                statusBanner
                EmptyStateView(systemImage: "bell", title: SettingsStrings.notificationsTitle)
            }
            .padding(.top, Spacing.medium)
        }
        .background(Palette.background)
        .navigationTitle(SettingsStrings.notificationsTitle)
    }

    @ViewBuilder private var statusBanner: some View {
        switch systemStatus {
        case .on:
            EmptyView()
        case .notAsked:
            BannerView(
                .info,
                message: SettingsStrings.statusNotAsked,
                actionTitle: SettingsStrings.turnOn,
                action: onRequestPermission
            )
            .padding(.horizontal, Spacing.medium)
        case .deliveredQuietly:
            BannerView(
                .info,
                message: SettingsStrings.statusQuiet,
                actionTitle: SettingsStrings.turnOnAlerts,
                action: onRequestPermission
            )
            .padding(.horizontal, Spacing.medium)
        case .offInSystemSettings:
            BannerView(
                .error,
                message: SettingsStrings.statusOff,
                actionTitle: SettingsStrings.openSettings,
                action: onOpenSystemSettings
            )
            .padding(.horizontal, Spacing.medium)
            .accessibilityIdentifier("notifications.systemOff")
        }
    }
}

/// Settings → Account: identity and Sign out behind the shared confirmation sheet.
public struct AccountSettingsView: View {
    let onSignOut: () -> Void
    @State private var isConfirmingSignOut = false

    public init(onSignOut: @escaping () -> Void) {
        self.onSignOut = onSignOut
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                EmptyStateView(systemImage: "lock.shield", title: SettingsStrings.accountTitle)
                WaiveraButton(SettingsStrings.signOut, variant: .destructive) {
                    isConfirmingSignOut = true
                }
                .padding(.horizontal, Spacing.medium)
                .accessibilityIdentifier("account.signOut")
            }
        }
        .background(Palette.background)
        .navigationTitle(SettingsStrings.accountTitle)
        .waiveraConfirmation(
            isPresented: $isConfirmingSignOut,
            title: SettingsStrings.signOutConfirmTitle,
            message: SettingsStrings.signOutConfirmMessage,
            confirmTitle: SettingsStrings.signOut,
            onConfirm: onSignOut
        )
    }
}

enum SettingsStrings {
    static var notificationsTitle: String { String(localized: "settings.notifications.title", bundle: .module) }
    static var accountTitle: String { String(localized: "settings.account.title", bundle: .module) }
    static var statusNotAsked: String { String(localized: "settings.notifications.status.notAsked", bundle: .module) }
    static var statusQuiet: String { String(localized: "settings.notifications.status.quiet", bundle: .module) }
    static var statusOff: String { String(localized: "settings.notifications.status.off", bundle: .module) }
    static var turnOn: String { String(localized: "settings.notifications.turnOn", bundle: .module) }
    static var turnOnAlerts: String { String(localized: "settings.notifications.turnOnAlerts", bundle: .module) }
    static var openSettings: String { String(localized: "settings.notifications.openSettings", bundle: .module) }
    static var signOut: String { String(localized: "settings.account.signOut", bundle: .module) }
    static var signOutConfirmTitle: String {
        String(localized: "settings.account.signOut.confirmTitle", bundle: .module)
    }
    static var signOutConfirmMessage: String {
        String(localized: "settings.account.signOut.confirmMessage", bundle: .module)
    }
}

#Preview("Light") {
    NavigationStack {
        NotificationSettingsView(systemStatus: .offInSystemSettings, onRequestPermission: {}, onOpenSystemSettings: {})
    }
}
#Preview("Dark") { NavigationStack { AccountSettingsView {} }.preferredColorScheme(.dark) }
#Preview("AX XXXL") {
    NavigationStack {
        NotificationSettingsView(systemStatus: .deliveredQuietly, onRequestPermission: {}, onOpenSystemSettings: {})
    }
    .dynamicTypeSize(.accessibility5)
}
