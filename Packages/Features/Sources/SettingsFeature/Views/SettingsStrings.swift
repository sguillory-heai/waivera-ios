#if canImport(UIKit)
    import Foundation
    import WaiveraData
    import WaiveraNotifications

    /// User-facing copy for the settings module. Values live in `Localizable.strings`.
    enum SettingsStrings {
        private static func text(_ key: String.LocalizationValue) -> String {
            String(localized: key, bundle: .module)
        }

        // Index
        static var title: String { text("settings.title") }
        static var preferencesSection: String { text("settings.section.preferences") }
        static var accountSection: String { text("settings.section.account") }
        static var notificationsRowDetail: String { text("settings.notifications.row.detail") }
        static var appearanceRowDetail: String { text("settings.appearance.row.detail") }
        static var signedIn: String { text("settings.account.unknown") }
        static var switchOn: String { text("settings.switch.on") }
        static var switchOff: String { text("settings.switch.off") }

        // Appearance
        static var appearanceTitle: String { text("settings.appearance.title") }
        static var themeSection: String { text("settings.theme.section") }
        static var feedbackSection: String { text("settings.feedback.section") }
        static var hapticsTitle: String { text("settings.haptics.title") }
        static var hapticsSubtitle: String { text("settings.haptics.subtitle") }

        static func theme(_ preference: AppearancePreference) -> (title: String, detail: String) {
            switch preference {
            case .system: (text("settings.theme.system"), text("settings.theme.system.detail"))
            case .light: (text("settings.theme.light"), text("settings.theme.light.detail"))
            case .dark: (text("settings.theme.dark"), text("settings.theme.dark.detail"))
            }
        }

        // Notifications
        static var notificationsTitle: String { text("settings.notifications.title") }
        static var statusNotAsked: String { text("settings.notifications.status.notAsked") }
        static var statusQuiet: String { text("settings.notifications.status.quiet") }
        static var statusOffTitle: String { text("settings.notifications.status.off.title") }
        static var statusOff: String { text("settings.notifications.status.off") }
        static var turnOn: String { text("settings.notifications.turnOn") }
        static var turnOnAlerts: String { text("settings.notifications.turnOnAlerts") }
        static var openSettings: String { text("settings.notifications.openSettings") }
        static var pushSection: String { text("settings.push.section") }
        static var pushTitle: String { text("settings.push.title") }
        static var pushSubtitle: String { text("settings.push.subtitle") }
        static var categoriesSection: String { text("settings.categories.section") }
        static var categoriesFooter: String { text("settings.categories.footer") }
        static var categoriesSystemOff: String { text("settings.categories.systemOff") }
        static var privacySection: String { text("settings.privacy.section") }
        static var previewsTitle: String { text("settings.previews.title") }
        static var previewsSubtitle: String { text("settings.previews.subtitle") }
        static var inAppSection: String { text("settings.inApp.section") }
        static var inAppBannersTitle: String { text("settings.inAppBanners.title") }
        static var inAppBannersSubtitle: String { text("settings.inAppBanners.subtitle") }
        static var inAppSoundTitle: String { text("settings.inAppSound.title") }
        static var inAppSoundSubtitle: String { text("settings.inAppSound.subtitle") }
        static var systemSection: String { text("settings.system.section") }
        static var systemExplainer: String { text("settings.system.explainer") }
        static var systemOpen: String { text("settings.system.open") }
        static var systemOpenHint: String { text("settings.system.open.hint") }

        static func category(_ meaning: NotificationMeaning) -> (title: String, detail: String) {
            switch meaning {
            case .messages:
                (text("settings.category.messages"), text("settings.category.messages.detail"))
            case .groupActivity:
                (text("settings.category.group_activity"), text("settings.category.group_activity.detail"))
            case .scheduleReminders:
                (text("settings.category.schedule_reminders"), text("settings.category.schedule_reminders.detail"))
            case .scheduleChanges:
                (text("settings.category.schedule_changes"), text("settings.category.schedule_changes.detail"))
            case .digest:
                (text("settings.category.digest"), text("settings.category.digest.detail"))
            }
        }

        // Account
        static var securitySection: String { text("settings.account.security") }
        static var changePassword: String { text("settings.account.changePassword") }
        static var changePasswordDetail: String { text("settings.account.changePassword.detail") }
        static var signOut: String { text("settings.account.signOut") }
        static var signingOut: String { text("settings.account.signingOut") }
        static var signOutDetail: String { text("settings.account.signOut.detail") }
        static var signOutConfirmTitle: String { text("settings.account.signOut.confirmTitle") }
        static var signOutConfirmMessage: String { text("settings.account.signOut.confirmMessage") }

        // Change password
        static var passwordTitle: String { text("settings.password.title") }
        static var passwordMessage: String { text("settings.password.message") }
        static var passwordCurrent: String { text("settings.password.current") }
        static var passwordNew: String { text("settings.password.new") }
        static var passwordConfirm: String { text("settings.password.confirm") }
        static func passwordHint(_ minimum: Int) -> String { text("settings.password.hint \(minimum)") }
        static var passwordSave: String { text("settings.password.save") }
        static var passwordCancel: String { text("settings.password.cancel") }
        static var passwordDone: String { text("settings.password.done") }
        static var passwordSuccess: String { text("settings.password.success") }

        static func passwordError(_ error: PasswordFieldError?) -> String? {
            switch error {
            case nil: nil
            case .currentRequired: text("settings.password.error.currentRequired")
            case .currentWrong: text("settings.password.error.currentWrong")
            case .tooShort(let minimum): text("settings.password.error.tooShort \(minimum)")
            case .sameAsCurrent: text("settings.password.error.same")
            case .mismatch: text("settings.password.error.mismatch")
            }
        }
    }
#endif
