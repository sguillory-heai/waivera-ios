#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Settings root: the signed-in identity, then Notifications, Appearance and Account.
    /// Rows navigate from their action (never a pressable nested in a link, 11-pitfalls #46).
    public struct SettingsView: View {
        @Environment(\.dataEnvironment) private var data
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
            Group {
                if let data {
                    SettingsIndexScreen(
                        model: AccountModel(environment: data),
                        onOpenNotifications: onOpenNotifications,
                        onOpenAppearance: onOpenAppearance,
                        onOpenAccount: onOpenAccount
                    )
                } else {
                    SettingsIndexContent(
                        account: nil,
                        onOpenNotifications: onOpenNotifications,
                        onOpenAppearance: onOpenAppearance,
                        onOpenAccount: onOpenAccount
                    )
                }
            }
            .background(Palette.background)
            .navigationTitle(SettingsStrings.title)
        }
    }

    private struct SettingsIndexScreen: View {
        @State private var model: AccountModel
        let onOpenNotifications: () -> Void
        let onOpenAppearance: () -> Void
        let onOpenAccount: () -> Void

        init(
            model: AccountModel,
            onOpenNotifications: @escaping () -> Void,
            onOpenAppearance: @escaping () -> Void,
            onOpenAccount: @escaping () -> Void
        ) {
            _model = State(initialValue: model)
            self.onOpenNotifications = onOpenNotifications
            self.onOpenAppearance = onOpenAppearance
            self.onOpenAccount = onOpenAccount
        }

        var body: some View {
            SettingsIndexContent(
                account: model.account,
                onOpenNotifications: onOpenNotifications,
                onOpenAppearance: onOpenAppearance,
                onOpenAccount: onOpenAccount
            )
            .task { await model.run() }
        }
    }

    struct SettingsIndexContent: View {
        let account: AccountSummary?
        let onOpenNotifications: () -> Void
        let onOpenAppearance: () -> Void
        let onOpenAccount: () -> Void

        var body: some View {
            List {
                if let account {
                    Section {
                        AccountHeader(account: account)
                            .listRowBackground(Palette.surface)
                    }
                }
                Section(SettingsStrings.preferencesSection) {
                    SettingsLinkRow(
                        title: SettingsStrings.notificationsTitle,
                        subtitle: SettingsStrings.notificationsRowDetail,
                        systemImage: "bell.fill",
                        action: onOpenNotifications
                    )
                    SettingsLinkRow(
                        title: SettingsStrings.appearanceTitle,
                        subtitle: SettingsStrings.appearanceRowDetail,
                        systemImage: "circle.lefthalf.filled",
                        action: onOpenAppearance
                    )
                }
                Section(SettingsStrings.accountSection) {
                    SettingsLinkRow(
                        title: SettingsStrings.accountTitle,
                        subtitle: SettingsStrings.accountRowDetail,
                        systemImage: "person.badge.key.fill",
                        action: onOpenAccount
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    /// Avatar initials, name and email at the top of Settings.
    struct AccountHeader: View {
        let account: AccountSummary

        var body: some View {
            let name = account.name ?? account.email ?? SettingsStrings.signedIn
            HStack(spacing: Spacing.smallPlus) {
                AvatarView(name: name)
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(name)
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.text)
                    if let email = account.email, email != name {
                        Text(email)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    if let organization = account.organization {
                        Text(organization)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.extraSmall)
            .accessibilityElement(children: .combine)
        }
    }

    /// A settings row that navigates from its action.
    struct SettingsLinkRow: View {
        let title: String
        let subtitle: String?
        let systemImage: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ListRow(title: title, subtitle: subtitle, showsChevron: true) {
                    IconTile(systemImage: systemImage)
                }
            }
            .buttonStyle(.pressScale)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.surface)
            .accessibilityAddTraits(.isButton)
        }
    }

    #if DEBUG
        private let previewAccount = AccountSummary(user: DemoData.make().user)

        #Preview("Light") {
            NavigationStack { SettingsView(onOpenNotifications: {}, onOpenAppearance: {}, onOpenAccount: {}) }
                .fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack {
                SettingsIndexContent(
                    account: previewAccount,
                    onOpenNotifications: {},
                    onOpenAppearance: {},
                    onOpenAccount: {}
                )
            }
            .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack {
                SettingsIndexContent(
                    account: previewAccount,
                    onOpenNotifications: {},
                    onOpenAppearance: {},
                    onOpenAccount: {}
                )
            }
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
