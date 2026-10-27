#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Email and password sign-in (01 §3). The app shows it whenever the session is signed out,
    /// and keeps it up while the backend bootstrap runs so the button can say "Connecting to
    /// Waivera…"; the gate moves on by itself when the session changes.
    public struct SignInView: View {
        @Environment(\.dataEnvironment) private var data
        private let injected: SignInModel?

        public init() {
            injected = nil
        }

        /// For previews and snapshot tests: renders a prepared model.
        public init(model: SignInModel) {
            injected = model
        }

        public var body: some View {
            Group {
                if let injected {
                    SignInContent(model: injected)
                } else {
                    SignInHost(session: data?.session)
                }
            }
            .accessibilityIdentifier("screen.sign-in")
        }
    }

    /// Owns the model for the lifetime of the screen and follows the session while it is visible.
    private struct SignInHost: View {
        @State private var model: SignInModel

        init(session: (any SessionRepository)?) {
            // Only the first value is kept; later inits of this view reuse the stored model.
            _model = State(
                initialValue: SignInModel(session: session, passwordReset: PasswordResetAdapter.sender(for: session))
            )
        }

        var body: some View {
            SignInContent(model: model)
                .task { await model.observeSession() }
        }
    }

    struct SignInContent: View {
        private enum Field: Hashable {
            case email
            case password
        }

        let model: SignInModel
        @FocusState private var focus: Field?

        var body: some View {
            AuthScaffold {
                hero
                notices
                AuthCard {
                    cardHeading
                    fields
                    buttons
                }
                Text(AuthStrings.footer)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .waiveraAnimation(.layout, value: model.notice)
            .authFeedback(failures: model.failureCount, successes: model.successCount)
            .onChange(of: model.emailIssue) { _, issue in
                if issue != nil { focus = .email }
            }
            .onChange(of: model.passwordIssue) { _, issue in
                if issue != nil, model.emailIssue == nil { focus = .password }
            }
        }

        private var hero: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(AuthStrings.brand)
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(AuthStrings.signInTitle)
                    .font(WaiveraFont.screenTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(AuthStrings.signInSubtitle)
                    .font(WaiveraFont.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }

        @ViewBuilder private var notices: some View {
            if !model.isConfigured {
                BannerView(.readOnly, message: configurationText)
                    .accessibilityIdentifier("signIn.configurationMissing")
            }
            switch model.notice {
            case .failed(let error):
                BannerView(.error, message: AuthStrings.failure(error), onDismiss: { model.dismissNotice() })
                    .authNoticeTransition()
                    .accessibilityIdentifier("signIn.error")
            case .resetSent(let email):
                BannerView(.info, message: AuthStrings.resetSentMessage(email), onDismiss: { model.dismissNotice() })
                    .authNoticeTransition()
                    .accessibilityIdentifier("signIn.resetSent")
            case nil:
                EmptyView()
            }
        }

        private var configurationText: String {
            let keys = ConfigurationReport.current.missingKeys
            let base = AuthStrings.configurationTitle + "\n" + AuthStrings.configurationMessage
            return keys.isEmpty ? base : base + "\n" + AuthStrings.configurationDetails(keys)
        }

        private var cardHeading: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(AuthStrings.signInCardTitle)
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(AuthStrings.signInCardSubtitle)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }

        /// Email (Return moves to the password) then password (Return submits). AutoFill pairs
        /// them through `.username` and `.password`.
        @ViewBuilder private var fields: some View {
            WaiveraTextField(
                AuthStrings.emailLabel,
                text: Binding(get: { model.email }, set: { model.setEmail($0) }),
                placeholder: AuthStrings.emailPlaceholder,
                error: model.emailIssue.map(AuthStrings.issue),
                contentType: .username,
                keyboard: .emailAddress
            )
            .focused($focus, equals: .email)
            .submitLabel(.next)
            .onSubmit { focus = .password }
            .disabled(!model.fieldsEnabled)
            .accessibilityIdentifier("signIn.email")
            WaiveraTextField(
                AuthStrings.passwordLabel,
                text: Binding(get: { model.password }, set: { model.setPassword($0) }),
                error: model.passwordIssue.map(AuthStrings.issue),
                isSecure: true,
                contentType: .password
            )
            .focused($focus, equals: .password)
            .submitLabel(.go)
            .onSubmit { submit() }
            .disabled(!model.fieldsEnabled)
            .accessibilityIdentifier("signIn.password")
        }

        @ViewBuilder private var buttons: some View {
            WaiveraButton(
                model.isConnecting ? AuthStrings.connecting : AuthStrings.signInButton,
                isLoading: model.isSigningIn,
                action: { submit() }
            )
            // Not dimmed while busy: the button ignores taps while it shows its spinner.
            .disabled(!model.canSubmit && !model.isSigningIn)
            .accessibilityIdentifier("signIn.submit")
            if model.isSigningIn {
                AuthProgressCaption(text: model.isConnecting ? AuthStrings.connecting : AuthStrings.signingIn)
            }
            if model.canResetPassword {
                WaiveraButton(
                    AuthStrings.forgotPassword,
                    variant: .plain,
                    isLoading: model.phase == .sendingReset,
                    action: { sendReset() }
                )
                .frame(maxWidth: .infinity)
                .disabled(!model.fieldsEnabled && model.phase != .sendingReset)
                .accessibilityIdentifier("signIn.forgotPassword")
            }
        }

        private func submit() {
            focus = nil
            // The model guards against a second submit; sign-in finishes even if the screen
            // goes away, because the session (not this view) owns what follows.
            Task { await model.submit() }
        }

        private func sendReset() {
            focus = nil
            Task { await model.sendPasswordReset() }
        }
    }

    #if DEBUG
        #Preview("Light") {
            FixturePreview {
                await AuthFixtures.signIn(.filled)
            } content: {
                SignInView(model: $0)
            }
        }
        #Preview("Dark, error") {
            FixturePreview {
                await AuthFixtures.signIn(.failed)
            } content: {
                SignInView(model: $0)
            }
            .preferredColorScheme(.dark)
        }
        #Preview("Connecting") {
            FixturePreview {
                await AuthFixtures.signIn(.connecting)
            } content: {
                SignInView(model: $0)
            }
        }
        #Preview("Reset sent") {
            FixturePreview {
                await AuthFixtures.signIn(.resetSent)
            } content: {
                SignInView(model: $0)
            }
        }
        #Preview("Configuration missing") {
            FixturePreview {
                await AuthFixtures.signIn(.configurationMissing)
            } content: {
                SignInView(model: $0)
            }
        }
        #Preview("AX XXXL, invalid") {
            FixturePreview {
                await AuthFixtures.signIn(.invalid)
            } content: {
                SignInView(model: $0)
            }
            .dynamicTypeSize(.accessibility5)
        }
        #Preview("Live fake") { SignInView().fakeDataEnvironment(.signedOut) }
    #endif
#endif
