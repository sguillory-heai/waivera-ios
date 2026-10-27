#if canImport(UserNotifications) && canImport(UIKit)
    import Foundation
    import UserNotifications
    import WaiveraNotifications

    /// Registers the meaning-based categories (plus the server's `CHAT_MESSAGE`) with Reply and
    /// Mark read actions.
    public enum NotificationCategoryRegistrar {
        public static func register(on center: UNUserNotificationCenter = .current()) {
            center.setNotificationCategories(makeCategories())
        }

        public static func makeCategories() -> Set<UNNotificationCategory> {
            Set(NotificationCategories.all.map(makeCategory))
        }

        static func makeCategory(_ definition: NotificationCategoryDefinition) -> UNNotificationCategory {
            UNNotificationCategory(
                identifier: definition.identifier,
                actions: definition.actions.map(makeAction),
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: LiveStrings.text(definition.hiddenPreviewsPlaceholderKey),
                options: []
            )
        }

        static func makeAction(_ definition: NotificationActionDefinition) -> UNNotificationAction {
            let options: UNNotificationActionOptions =
                definition.requiresAuthentication ? [.authenticationRequired] : []
            switch definition.kind {
            case .plain:
                return UNNotificationAction(
                    identifier: definition.identifier,
                    title: LiveStrings.text(definition.titleKey),
                    options: options,
                    icon: UNNotificationActionIcon(systemImageName: "checkmark.message")
                )
            case .textInput(let buttonTitleKey, let placeholderKey):
                return UNTextInputNotificationAction(
                    identifier: definition.identifier,
                    title: LiveStrings.text(definition.titleKey),
                    options: options,
                    icon: UNNotificationActionIcon(systemImageName: "arrowshape.turn.up.left"),
                    textInputButtonTitle: LiveStrings.text(buttonTitleKey),
                    textInputPlaceholder: LiveStrings.text(placeholderKey)
                )
            }
        }
    }

    enum LiveStrings {
        static func text(_ key: String) -> String {
            Bundle.module.localizedString(forKey: key, value: nil, table: nil)
        }
    }
#endif
