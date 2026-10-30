#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Settings (Android `SettingsScreen`): Preferences (Notifications, Appearance), Security
    /// (Change password, only when `onOpenChangePassword` is given) and Account, where the
    /// signed-in identity sits above Sign out. Sign out asks first on the shared confirmation
    /// sheet; `onSignOut` is the app's single sign-out path, which unregisters the push token,
    /// stops realtime, clears caches and signs out of Firebase.
    public struct SettingsView: View {
        @Environment(\.dataEnvironment) private var data
        let actions: SettingsActions

        public init(
            onOpenNotifications: @escaping () -> Void,
            onOpenAppearance: @escaping () -> Void,
            onOpenChangePassword: (() -> Void)? = nil,
            onSignOut: @escaping () -> Void
        ) {
            actions = SettingsActions(
                openNotifications: onOpenNotifications,
                openAppearance: onOpenAppearance,
                openChangePassword: onOpenChangePassword,
                signOut: onSignOut
            )
        }

        public var body: some View {
            Group {
                if let data {
                    SettingsScreen(model: AccountModel(environment: data), actions: actions)
                } else {
                    SettingsContent(account: nil, isSigningOut: false, actions: actions, requestSignOut: {})
                }
            }
            .navigationTitle(SettingsStrings.title)
            .accessibilityIdentifier("screen.settings")
        }
    }

    struct SettingsActions {
        var openNotifications: () -> Void = {}
        var openAppearance: () -> Void = {}
        var openChangePassword: (() -> Void)?
        var signOut: () -> Void = {}
    }

    private struct SettingsScreen: View {
        @State private var model: AccountModel
        let actions: SettingsActions

        init(model: AccountModel, actions: SettingsActions) {
            _model = State(initialValue: model)
            self.actions = actions
        }

        var body: some View {
            SettingsContent(
                account: model.account,
                isSigningOut: model.isSigningOut,
                actions: actions,
                requestSignOut: { model.requestSignOut() }
            )
            .task { await model.run() }
            .sheet(
                isPresented: Binding(
                    get: { model.isConfirmingSignOut },
                    set: { model.setConfirmingSignOut($0) }
                )
            ) {
                ConfirmationSheet(
                    title: SettingsStrings.signOutConfirmTitle,
                    message: SettingsStrings.signOutConfirmMessage,
                    confirmTitle: SettingsStrings.signOut,
                    isConfirming: model.isSigningOut,
                    confirmingTitle: SettingsStrings.signingOut,
                    dismissesOnConfirm: false
                ) {
                    if model.confirmSignOut() { actions.signOut() }
                }
                .waiveraSheetPresentation()
            }
        }
    }

    struct SettingsContent: View {
        let account: AccountSummary?
        let isSigningOut: Bool
        let actions: SettingsActions
        let requestSignOut: () -> Void

        var body: some View {
            // Every section stays on screen while signing out, so nothing jumps; the rows just
            // stop taking taps until the sign-out finishes.
            SettingsPage {
                SectionHeader(SettingsStrings.preferencesSection)
                CardGroup {
                    SettingsLinkRow(
                        title: SettingsStrings.notificationsTitle,
                        subtitle: SettingsStrings.notificationsRowDetail,
                        systemImage: "bell.fill",
                        tone: .amber,
                        action: actions.openNotifications
                    )
                    .accessibilityIdentifier("settings.notifications")
                    SettingsRowDivider()
                    SettingsLinkRow(
                        title: SettingsStrings.appearanceTitle,
                        subtitle: SettingsStrings.appearanceRowDetail,
                        systemImage: "paintpalette.fill",
                        tone: .rose,
                        action: actions.openAppearance
                    )
                    .accessibilityIdentifier("settings.appearance")
                }
                .disabled(isSigningOut)
                if let openChangePassword = actions.openChangePassword {
                    SectionHeader(SettingsStrings.securitySection)
                    CardGroup {
                        SettingsLinkRow(
                            title: SettingsStrings.changePassword,
                            subtitle: SettingsStrings.changePasswordDetail,
                            systemImage: "lock.fill",
                            action: openChangePassword
                        )
                        .accessibilityIdentifier("account.changePassword")
                    }
                    .disabled(account == nil || isSigningOut)
                }
                SectionHeader(SettingsStrings.accountSection)
                AccountCard(account: account, isSigningOut: isSigningOut, onSignOut: requestSignOut)
            }
        }
    }

    /// The signed-in identity, then Sign out (the outlined destructive button: it should not
    /// shout) and what signing out does.
    private struct AccountCard: View {
        let account: AccountSummary?
        let isSigningOut: Bool
        let onSignOut: () -> Void

        var body: some View {
            CardGroup {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    if let account {
                        AccountHeader(account: account)
                    }
                    WaiveraButton(
                        SettingsStrings.signOut,
                        variant: .destructiveOutline,
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isLoading: isSigningOut,
                        loadingTitle: SettingsStrings.signingOut,
                        fillsWidth: true,
                        action: onSignOut
                    )
                    .disabled(account == nil && !isSigningOut)
                    .accessibilityIdentifier("account.signOut")
                    Text(SettingsStrings.signOutDetail)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.mediumSmall)
            }
        }
    }

    /// Avatar, name, email and organization, read as one sentence.
    struct AccountHeader: View {
        let account: AccountSummary

        var body: some View {
            let name = account.name ?? account.email ?? SettingsStrings.signedIn
            HStack(spacing: Spacing.mediumSmall) {
                AvatarView(name: name, size: ControlSize.avatarMedium)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    NameText(name, style: .titleMedium, lines: 2)
                        .foregroundStyle(Palette.text)
                    if let email = account.email, email != name {
                        Text(email)
                            .waiveraTextStyle(.bodyMedium)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    if let organization = account.organization {
                        Text(organization)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.small)
            .accessibilityElement(children: .combine)
        }
    }

    #if DEBUG
        private let previewAccount = AccountSummary(user: DemoData.make().user)

        #Preview("Light") {
            NavigationStack {
                SettingsView(onOpenNotifications: {}, onOpenAppearance: {}, onOpenChangePassword: {}, onSignOut: {})
            }
            .fakeDataEnvironment()
        }
        #Preview("Dark, signing out") {
            NavigationStack {
                SettingsContent(
                    account: previewAccount,
                    isSigningOut: true,
                    actions: SettingsActions(openChangePassword: {}),
                    requestSignOut: {}
                )
            }
            .preferredColorScheme(.dark)
        }
        #Preview("AX5") {
            NavigationStack {
                SettingsContent(
                    account: previewAccount,
                    isSigningOut: false,
                    actions: SettingsActions(openChangePassword: {}),
                    requestSignOut: {}
                )
            }
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
