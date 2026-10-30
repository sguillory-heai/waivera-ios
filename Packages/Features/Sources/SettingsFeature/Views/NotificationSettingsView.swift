#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign
    import WaiveraNotifications

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Settings → Notifications (Android `NotificationSettingsScreen`). The system permission
    /// comes first: when iOS has not been asked, delivers quietly or blocks the app, a banner says
    /// so with the action that fixes it (09-push §5). Then the push master switch, the categories
    /// by meaning, previews, the in-app alert switches and a link to the app's iOS notification
    /// settings for sounds, banner style and lock screen. While push is off or iOS blocks the app,
    /// the dependent switches are dimmed with a line saying why, and keep their stored values.
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
                        actions: actions
                    )
                } else {
                    NotificationSettingsContent(
                        preferences: NotificationPreferences(),
                        systemStatus: systemStatus,
                        actions: actions
                    )
                }
            }
            .navigationTitle(SettingsStrings.notificationsTitle)
            .accessibilityIdentifier("screen.settings-notifications")
        }

        private var actions: NotificationSettingsActions {
            NotificationSettingsActions(
                requestPermission: onRequestPermission,
                openSystemSettings: onOpenSystemSettings
            )
        }
    }

    private struct NotificationSettingsScreen: View {
        @State private var model: NotificationSettingsModel
        let systemStatus: SystemNotificationStatus
        let actions: NotificationSettingsActions

        init(
            model: NotificationSettingsModel,
            systemStatus: SystemNotificationStatus,
            actions: NotificationSettingsActions
        ) {
            _model = State(initialValue: model)
            self.systemStatus = systemStatus
            self.actions = actions
        }

        var body: some View {
            var live = actions
            live.apply = { model.apply($0) }
            return NotificationSettingsContent(
                preferences: model.preferences,
                systemStatus: systemStatus,
                actions: live
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
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let preferences: NotificationPreferences
        let systemStatus: SystemNotificationStatus
        let actions: NotificationSettingsActions

        private var block: NotificationSwitchBlock? {
            NotificationSwitches.block(pushEnabled: preferences.pushEnabled, system: systemStatus)
        }

        var body: some View {
            SettingsPage {
                SystemStatusBanner(status: systemStatus, actions: actions)
                    .padding(.top, Spacing.small)
                SectionHeader(SettingsStrings.pushSection)
                CardGroup {
                    SettingsToggleRow(
                        title: SettingsStrings.pushTitle,
                        subtitle: SettingsStrings.pushSubtitle,
                        systemImage: "bell.fill",
                        tone: .amber,
                        isOn: preferences.pushEnabled
                    ) { actions.apply(.push($0)) }
                    .accessibilityIdentifier("notifications.push")
                }
                SectionHeader(SettingsStrings.categoriesSection)
                if let block {
                    // Says why the switches below are off instead of leaving them silently dimmed.
                    SettingsNote(
                        text: block == .systemOff
                            ? SettingsStrings.categoriesSystemOff : SettingsStrings.categoriesFooter
                    )
                    .transition(.opacity)
                }
                CardGroup {
                    ForEach(Array(NotificationSwitches.offered.enumerated()), id: \.element) { index, meaning in
                        if index > 0 {
                            SettingsRowDivider()
                        }
                        let copy = SettingsStrings.category(meaning)
                        SettingsToggleRow(
                            title: copy.title,
                            subtitle: copy.detail,
                            systemImage: meaning.systemImage,
                            tone: meaning.tone,
                            isEnabled: block == nil,
                            isOn: NotificationSwitches.isOn(meaning, in: preferences)
                        ) { actions.apply(.meaning(meaning, $0)) }
                        .accessibilityIdentifier("notifications.\(meaning.rawValue)")
                    }
                }
                SectionHeader(SettingsStrings.privacySection)
                CardGroup {
                    SettingsToggleRow(
                        title: SettingsStrings.previewsTitle,
                        subtitle: SettingsStrings.previewsSubtitle,
                        systemImage: "lock.fill",
                        isEnabled: block == nil,
                        isOn: preferences.previewContent
                    ) { actions.apply(.previews($0)) }
                    .accessibilityIdentifier("notifications.previews")
                }
                SectionHeader(SettingsStrings.inAppSection)
                CardGroup {
                    SettingsToggleRow(
                        title: SettingsStrings.inAppBannersTitle,
                        subtitle: SettingsStrings.inAppBannersSubtitle,
                        systemImage: "rectangle.topthird.inset.filled",
                        isEnabled: block == nil,
                        isOn: preferences.inAppBanners
                    ) { actions.apply(.inAppBanners($0)) }
                    .accessibilityIdentifier("notifications.inAppBanners")
                    SettingsRowDivider()
                    SettingsToggleRow(
                        title: SettingsStrings.inAppSoundTitle,
                        subtitle: SettingsStrings.inAppSoundSubtitle,
                        systemImage: "speaker.wave.2.fill",
                        isEnabled: block == nil,
                        isOn: preferences.sound
                    ) { actions.apply(.inAppSound($0)) }
                    .accessibilityIdentifier("notifications.inAppSound")
                }
                SectionHeader(SettingsStrings.systemSection)
                SettingsNote(text: SettingsStrings.systemExplainer)
                CardGroup {
                    Button(action: actions.openSystemSettings) {
                        ListRow(title: SettingsStrings.systemOpen) {
                            IconTile(systemImage: "gearshape.fill", tone: .neutral)
                        } trailing: {
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundStyle(Palette.textSecondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.press(.row))
                    .accessibilityHint(Text(SettingsStrings.systemOpenHint))
                    .accessibilityIdentifier("notifications.openSystemSettings")
                }
            }
            .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: block)
        }
    }

    /// The permission banner: nothing when notifications are on. "Not asked" and quiet delivery
    /// are information with the fix; blocked by iOS is a warning that opens Settings.
    private struct SystemStatusBanner: View {
        let status: SystemNotificationStatus
        let actions: NotificationSettingsActions

        var body: some View {
            switch status {
            case .enabled:
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
                    .warning,
                    title: SettingsStrings.statusOffTitle,
                    message: SettingsStrings.statusOff,
                    actionTitle: SettingsStrings.openSettings,
                    action: actions.openSystemSettings
                )
                .accessibilityIdentifier("notifications.systemOff")
            }
        }
    }

    extension NotificationMeaning {
        /// The same tile as the primer, so a category looks the same wherever it is explained.
        fileprivate var systemImage: String {
            switch self {
            case .messages: "bubble.left.and.bubble.right.fill"
            case .groupActivity: "person.2.fill"
            case .scheduleReminders: "clock.fill"
            case .scheduleChanges: "calendar"
            case .digest: "megaphone.fill"
            }
        }

        fileprivate var tone: TileTone {
            switch self {
            case .messages, .groupActivity: .brand
            case .scheduleReminders, .scheduleChanges: .teal
            case .digest: .amber
            }
        }
    }

    #if DEBUG
        private func pushOff() -> NotificationPreferences {
            var preferences = NotificationPreferences()
            preferences.pushEnabled = false
            return preferences
        }

        #Preview("Light, blocked by iOS") {
            NavigationStack {
                NotificationSettingsView(
                    systemStatus: .offInSystemSettings,
                    onRequestPermission: {},
                    onOpenSystemSettings: {}
                )
            }
            .fakeDataEnvironment()
        }
        #Preview("Dark, push off") {
            NavigationStack {
                NotificationSettingsContent(
                    preferences: pushOff(),
                    systemStatus: .enabled,
                    actions: NotificationSettingsActions()
                )
            }
            .preferredColorScheme(.dark)
        }
        #Preview("AX5") {
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
