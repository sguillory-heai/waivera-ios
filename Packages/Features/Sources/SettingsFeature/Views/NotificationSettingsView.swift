#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign
    import WaiveraNotifications

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Settings → Notifications. Shows the system permission state first: when notifications are
    /// off at the system level it says so and links to iOS Settings (09-push §5). Then the push
    /// master switch, the categories by meaning, previews, the in-app alert switches and a link
    /// to the app's iOS notification settings for sounds, banner style and lock screen.
    public struct NotificationSettingsView: View {
        @Environment(\.dataEnvironment) private var data
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
            Group {
                if let data {
                    NotificationSettingsScreen(
                        model: NotificationSettingsModel(environment: data),
                        systemStatus: systemStatus,
                        onRequestPermission: onRequestPermission,
                        onOpenSystemSettings: onOpenSystemSettings
                    )
                } else {
                    NotificationSettingsContent(
                        preferences: NotificationPreferences(),
                        systemStatus: systemStatus,
                        actions: NotificationSettingsActions(
                            requestPermission: onRequestPermission,
                            openSystemSettings: onOpenSystemSettings
                        )
                    )
                }
            }
            .background(Palette.background)
            .navigationTitle(SettingsStrings.notificationsTitle)
        }
    }

    private struct NotificationSettingsScreen: View {
        @State private var model: NotificationSettingsModel
        let systemStatus: SystemNotificationStatus
        let onRequestPermission: () -> Void
        let onOpenSystemSettings: () -> Void

        init(
            model: NotificationSettingsModel,
            systemStatus: SystemNotificationStatus,
            onRequestPermission: @escaping () -> Void,
            onOpenSystemSettings: @escaping () -> Void
        ) {
            _model = State(initialValue: model)
            self.systemStatus = systemStatus
            self.onRequestPermission = onRequestPermission
            self.onOpenSystemSettings = onOpenSystemSettings
        }

        var body: some View {
            NotificationSettingsContent(
                preferences: model.preferences,
                systemStatus: systemStatus,
                actions: NotificationSettingsActions(
                    requestPermission: onRequestPermission,
                    openSystemSettings: onOpenSystemSettings,
                    apply: { model.apply($0) }
                )
            )
            .task { await model.run() }
        }
    }

    struct NotificationSettingsActions {
        var requestPermission: () -> Void = {}
        var openSystemSettings: () -> Void = {}
        var apply: (NotificationSettingsModel.Change) -> Void = { _ in }
    }

    struct NotificationSettingsContent: View {
        let preferences: NotificationPreferences
        let systemStatus: SystemNotificationStatus
        let actions: NotificationSettingsActions

        private var categoriesEnabled: Bool { preferences.pushEnabled }

        var body: some View {
            List {
                if systemStatus != .on {
                    Section {
                        statusBanner
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                Section(SettingsStrings.pushSection) {
                    toggle(
                        SettingsStrings.pushTitle,
                        SettingsStrings.pushSubtitle,
                        isOn: preferences.pushEnabled,
                        id: "notifications.push"
                    ) { actions.apply(.push($0)) }
                }
                Section {
                    ForEach(NotificationSwitches.offered, id: \.self) { meaning in
                        let copy = SettingsStrings.category(meaning)
                        dependent(
                            toggle(
                                copy.title,
                                copy.detail,
                                isOn: NotificationSwitches.isOn(meaning, in: preferences),
                                id: "notifications.\(meaning.rawValue)"
                            ) { actions.apply(.meaning(meaning, $0)) }
                        )
                    }
                } header: {
                    Text(SettingsStrings.categoriesSection)
                } footer: {
                    if !categoriesEnabled { Text(SettingsStrings.categoriesFooter) }
                }
                Section(SettingsStrings.privacySection) {
                    dependent(
                        toggle(
                            SettingsStrings.previewsTitle,
                            SettingsStrings.previewsSubtitle,
                            isOn: preferences.previewContent,
                            id: "notifications.previews"
                        ) { actions.apply(.previews($0)) }
                    )
                }
                Section(SettingsStrings.inAppSection) {
                    dependent(
                        toggle(
                            SettingsStrings.inAppBannersTitle,
                            SettingsStrings.inAppBannersSubtitle,
                            isOn: preferences.inAppBanners,
                            id: "notifications.inAppBanners"
                        ) { actions.apply(.inAppBanners($0)) }
                    )
                    dependent(
                        toggle(
                            SettingsStrings.inAppSoundTitle,
                            SettingsStrings.inAppSoundSubtitle,
                            isOn: preferences.sound,
                            id: "notifications.inAppSound"
                        ) { actions.apply(.inAppSound($0)) }
                    )
                }
                Section {
                    Text(SettingsStrings.systemExplainer)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .listRowBackground(Palette.surface)
                    SettingsLinkRow(
                        title: SettingsStrings.systemOpen,
                        subtitle: nil,
                        systemImage: "gear",
                        action: actions.openSystemSettings
                    )
                    .accessibilityIdentifier("notifications.openSystemSettings")
                } header: {
                    Text(SettingsStrings.systemSection)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }

        private func toggle(
            _ title: String,
            _ subtitle: String,
            isOn: Bool,
            id: String,
            set: @escaping (Bool) -> Void
        ) -> some View {
            ToggleRow(title, subtitle: subtitle, isOn: Binding(get: { isOn }, set: set))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.surface)
                .accessibilityIdentifier(id)
        }

        /// Dimmed and disabled while push is off; the stored value is kept (08 §8).
        private func dependent(_ row: some View) -> some View {
            row
                .disabled(!categoriesEnabled)
                .opacity(categoriesEnabled ? 1 : Emphasis.disabled)
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
                    action: actions.requestPermission
                )
            case .deliveredQuietly:
                BannerView(
                    .info,
                    message: SettingsStrings.statusQuiet,
                    actionTitle: SettingsStrings.turnOnAlerts,
                    action: actions.requestPermission
                )
            case .offInSystemSettings:
                BannerView(
                    .error,
                    message: SettingsStrings.statusOff,
                    actionTitle: SettingsStrings.openSettings,
                    action: actions.openSystemSettings
                )
                .accessibilityIdentifier("notifications.systemOff")
            }
        }
    }

    #if DEBUG
        private func pushOff() -> NotificationPreferences {
            var preferences = NotificationPreferences()
            preferences.pushEnabled = false
            return preferences
        }

        #Preview("Light") {
            NavigationStack {
                NotificationSettingsView(
                    systemStatus: .offInSystemSettings,
                    onRequestPermission: {},
                    onOpenSystemSettings: {}
                )
            }
            .fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack {
                NotificationSettingsContent(
                    preferences: pushOff(),
                    systemStatus: .on,
                    actions: NotificationSettingsActions()
                )
            }
            .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack {
                NotificationSettingsContent(
                    preferences: NotificationPreferences(),
                    systemStatus: .deliveredQuietly,
                    actions: NotificationSettingsActions()
                )
            }
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
