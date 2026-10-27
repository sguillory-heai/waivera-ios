#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Settings → Account: identity, the voluntary password change, and Sign out behind the
    /// shared confirmation sheet. `onSignOut` is the app's single sign-out path, which unregisters
    /// the push token, stops realtime, clears caches and signs out of Firebase.
    ///
    /// `onChangePassword` lets the app push its change-password route (which a deep link also
    /// opens); without it the row presents this feature's own sheet.
    public struct AccountSettingsView: View {
        @Environment(\.dataEnvironment) private var data
        let onSignOut: () -> Void
        let onChangePassword: (() -> Void)?

        public init(onChangePassword: (() -> Void)? = nil, onSignOut: @escaping () -> Void) {
            self.onChangePassword = onChangePassword
            self.onSignOut = onSignOut
        }

        public var body: some View {
            Group {
                if let data {
                    AccountScreen(
                        model: AccountModel(environment: data),
                        session: data.session,
                        onChangePassword: onChangePassword,
                        onSignOut: onSignOut
                    )
                } else {
                    AccountContent(account: nil, isSigningOut: false, actions: AccountActions(signOut: onSignOut))
                }
            }
            .background(Palette.background)
            .navigationTitle(SettingsStrings.accountTitle)
        }
    }

    private struct AccountScreen: View {
        @State private var model: AccountModel
        @State private var isChangingPassword = false
        let session: any SessionRepository
        let onChangePassword: (() -> Void)?
        let onSignOut: () -> Void

        init(
            model: AccountModel,
            session: any SessionRepository,
            onChangePassword: (() -> Void)?,
            onSignOut: @escaping () -> Void
        ) {
            _model = State(initialValue: model)
            self.session = session
            self.onChangePassword = onChangePassword
            self.onSignOut = onSignOut
        }

        var body: some View {
            AccountContent(
                account: model.account,
                isSigningOut: model.isSigningOut,
                actions: AccountActions(
                    changePassword: {
                        if let onChangePassword { onChangePassword() } else { isChangingPassword = true }
                    },
                    signOut: { model.requestSignOut() }
                )
            )
            .task { await model.run() }
            .waiveraConfirmation(
                isPresented: $model.isConfirmingSignOut,
                title: SettingsStrings.signOutConfirmTitle,
                message: SettingsStrings.signOutConfirmMessage,
                confirmTitle: SettingsStrings.signOut
            ) {
                if model.confirmSignOut() { onSignOut() }
            }
            .sheet(isPresented: $isChangingPassword) {
                ChangePasswordSheet(model: ChangePasswordModel(session: session))
            }
        }
    }

    struct AccountActions {
        var changePassword: () -> Void = {}
        var signOut: () -> Void = {}
    }

    struct AccountContent: View {
        let account: AccountSummary?
        let isSigningOut: Bool
        let actions: AccountActions
        @State private var diagnosticsCopied = false

        var body: some View {
            List {
                if let account {
                    Section {
                        AccountHeader(account: account)
                            .listRowBackground(Palette.surface)
                    }
                }
                Section(SettingsStrings.securitySection) {
                    SettingsLinkRow(
                        title: SettingsStrings.changePassword,
                        subtitle: SettingsStrings.changePasswordDetail,
                        systemImage: "key.fill",
                        action: actions.changePassword
                    )
                    .disabled(account == nil || isSigningOut)
                    .accessibilityIdentifier("account.changePassword")
                }
                Section {
                    WaiveraButton(
                        SettingsStrings.signOut,
                        variant: .destructive,
                        systemImage: "rectangle.portrait.and.arrow.right",
                        isLoading: isSigningOut,
                        action: actions.signOut
                    )
                    .disabled(isSigningOut)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("account.signOut")
                } footer: {
                    Text(SettingsStrings.signOutDetail)
                }
                #if DEBUG
                    if let account {
                        Section {
                            Button(diagnosticsCopied ? SettingsStrings.diagnosticsCopied : SettingsStrings.diagnostics)
                            {
                                UIPasteboard.general.string = Self.diagnostics(account)
                                diagnosticsCopied = true
                            }
                            .foregroundStyle(Palette.accent)
                            .frame(minHeight: ControlSize.minHitTarget)
                            .listRowBackground(Palette.surface)
                            .waiveraHaptic(.success, trigger: diagnosticsCopied)
                        }
                    }
                #endif
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }

        #if DEBUG
            /// Development builds only: organization and app version, never tokens or ids.
            private static func diagnostics(_ account: AccountSummary) -> String {
                let info = Bundle.main.infoDictionary
                let version = info?["CFBundleShortVersionString"] as? String ?? "?"
                let build = info?["CFBundleVersion"] as? String ?? "?"
                return "Waivera \(version) (\(build)); organization: \(account.organization ?? "-")"
            }
        #endif
    }

    #if DEBUG
        private let accountPreview = AccountSummary(user: DemoData.make().user)

        #Preview("Light") {
            NavigationStack { AccountSettingsView {} }.fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack { AccountContent(account: accountPreview, isSigningOut: false, actions: AccountActions()) }
                .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack { AccountContent(account: accountPreview, isSigningOut: true, actions: AccountActions()) }
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
