#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Email and password sign-in (01 §3, Android `SignInScreen`). The app shows it whenever the
    /// session is signed out, and keeps it up while the backend bootstrap runs so the button can
    /// say "Signing you in…"; the gate moves on by itself when the session changes.
    ///
    /// The brand header with the real logo, then the curved sheet with "Welcome back", any
    /// message, the two fields, Sign in, Forgot password? and the legal links. No tagline or
    /// reassurance copy: everything on it helps someone sign in.
    public struct SignInView: View {
        @Environment(\.dataEnvironment) private var data
        private let injected: SignInModel?
        private let legalLinks: LegalLinks?

        /// `legalLinks` come from the build's web base (`LegalLinks.from(webBase:)`); `nil`
        /// hides the legal sentence, so the screen never shows a dead link.
        public init(legalLinks: LegalLinks? = nil) {
            injected = nil
            self.legalLinks = legalLinks
        }

        /// For previews and snapshot tests: renders a prepared model.
        public init(model: SignInModel, legalLinks: LegalLinks? = nil) {
            injected = model
            self.legalLinks = legalLinks
        }

        public var body: some View {
            Group {
                if let injected {
                    SignInContent(model: injected, legalLinks: legalLinks)
                } else {
                    SignInHost(session: data?.session, legalLinks: legalLinks)
                }
            }
            .accessibilityIdentifier("screen.sign-in")
        }
    }

    /// Owns the model for the lifetime of the screen and follows the session while it is visible.
    private struct SignInHost: View {
        @State private var model: SignInModel
        let legalLinks: LegalLinks?

        init(session: (any SessionRepository)?, legalLinks: LegalLinks?) {
            // Only the first value is kept; later inits of this view reuse the stored model.
            _model = State(initialValue: SignInModel(session: session))
            self.legalLinks = legalLinks
        }

        var body: some View {
            SignInContent(model: model, legalLinks: legalLinks)
                .task { await model.observeSession() }
        }
    }

    struct SignInContent: View {
        enum Field: Hashable {
            case email
            case password
        }

        let model: SignInModel
        let legalLinks: LegalLinks?
        @FocusState private var focus: Field?
        @Environment(\.openURL) private var openURL

        var body: some View {
            SignInFrame(compact: focus != nil) {
                Text(AuthStrings.signInTitle)
                    .modifier(SignInTitleStyle())
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                // The banner shakes with the fields it explains, so a rejection is one "no" rather
                // than a shake on top of the banner pushing the form down (M2-09). The shake waits
                // for the banner's push (`rejectShake`); the vibration does not.
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    SignInNotices(model: model)
                    fields
                        .padding(.top, Spacing.small)
                }
                .rejectShake(trigger: model.rejectionCount)
                buttons
                    .padding(.top, Spacing.mediumSmall)
            } footer: {
                if let legalLinks {
                    LegalFooter(links: legalLinks, onOpen: open)
                }
            }
            .waiveraAnimation(.layout, value: model.notice)
            .waiveraAnimation(.layout, value: model.isConfigured)
            .signInRejectedFeedback(rejections: model.rejectionCount)
            .onChange(of: model.emailIssue) { _, issue in
                if issue != nil { focus = .email }
            }
            .onChange(of: model.passwordIssue) { _, issue in
                if issue != nil, model.emailIssue == nil { focus = .password }
            }
        }

        /// Email (Return moves to the password) then password (Return submits). AutoFill pairs
        /// them through `.username` and `.password`.
        private var fields: some View {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                WaiveraTextField(
                    AuthStrings.emailLabel,
                    text: Binding(get: { model.email }, set: { model.setEmail($0) }),
                    focus: $focus,
                    field: .email,
                    placeholder: AuthStrings.emailPlaceholder,
                    error: model.emailIssue.map(AuthStrings.issue),
                    contentType: .username,
                    keyboard: .emailAddress,
                    systemImage: "envelope",
                    accessibilityIdentifier: "signIn.email"
                )
                .submitLabel(.next)
                .onSubmit { focus = .password }
                .disabled(!model.fieldsEnabled)
                WaiveraTextField(
                    AuthStrings.passwordLabel,
                    text: Binding(get: { model.password }, set: { model.setPassword($0) }),
                    focus: $focus,
                    field: .password,
                    placeholder: AuthStrings.passwordPlaceholder,
                    error: model.passwordIssue.map(AuthStrings.issue),
                    isSecure: true,
                    contentType: .password,
                    systemImage: "lock",
                    accessibilityIdentifier: "signIn.password"
                )
                .submitLabel(.go)
                .onSubmit { submit() }
                .disabled(!model.fieldsEnabled)
            }
        }

        /// The 56pt primary Sign in, with Forgot password? centred under it.
        private var buttons: some View {
            VStack(spacing: Spacing.extraSmall) {
                WaiveraButton(
                    AuthStrings.signInButton,
                    size: .large,
                    isLoading: model.isSigningIn,
                    loadingTitle: AuthStrings.connecting,
                    action: { submit() }
                )
                // Enabled with empty fields so a tap explains what is missing (field errors)
                // instead of a dimmed button that says nothing; enabled while busy so the spinner
                // is not dimmed (the button ignores taps while it shows it).
                .disabled(!model.fieldsEnabled && !model.isSigningIn)
                .accessibilityIdentifier("signIn.submit")
                if model.canResetPassword {
                    WaiveraButton(
                        AuthStrings.forgotPassword,
                        variant: .text,
                        isLoading: model.phase == .sendingReset,
                        loadingTitle: AuthStrings.resetSending,
                        fillsWidth: true,
                        action: { sendReset() }
                    )
                    .disabled(!model.fieldsEnabled && model.phase != .sendingReset)
                    .accessibilityIdentifier("signIn.forgotPassword")
                }
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

        /// Opens a legal page in the browser through the app's link policy. When nothing can open
        /// it, the screen says so calmly; the person's typing is untouched.
        private func open(_ url: URL) {
            openURL(url) { accepted in
                if !accepted { model.linkUnavailable() }
            }
        }
    }

    /// "Welcome back": the concept's 30 / 800, one step down at large text so it keeps to two lines.
    private struct SignInTitleStyle: ViewModifier {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        func body(content: Content) -> some View {
            content.waiveraTextStyle(dynamicTypeSize.isLargeText ? .headlineMedium : .headlineLarge)
        }
    }

    /// The banners above the fields: configuration, failure, reset sent and a link that would not
    /// open. Each opens downward from its top, an even push of the form below.
    private struct SignInNotices: View {
        let model: SignInModel

        var body: some View {
            if !model.isConfigured {
                BannerView(.warning, title: AuthStrings.configurationTitle, message: configurationText)
                    .authNoticeTransition()
                    .accessibilityIdentifier("signIn.configurationMissing")
            }
            switch model.notice {
            case .failed(let error):
                BannerView(
                    .error,
                    title: AuthStrings.signInFailedTitle,
                    message: AuthStrings.failure(error),
                    onDismiss: { model.dismissNotice() }
                )
                .authNoticeTransition()
                .accessibilityIdentifier("signIn.error")
            case .resetSent(let email):
                BannerView(
                    .info,
                    title: AuthStrings.resetSentTitle,
                    message: AuthStrings.resetSentMessage(email),
                    onDismiss: { model.dismissNotice() }
                )
                .authNoticeTransition()
                .accessibilityIdentifier("signIn.resetSent")
            case .linkUnavailable:
                BannerView(
                    .warning,
                    title: AuthStrings.linkFailedTitle,
                    message: AuthStrings.linkFailedMessage,
                    onDismiss: { model.dismissNotice() }
                )
                .authNoticeTransition()
                .accessibilityIdentifier("signIn.linkFailed")
            case nil:
                EmptyView()
            }
        }

        /// The raw setting names help a developer and mean nothing to staff: DEBUG builds only.
        private var configurationText: String {
            let keys = ConfigurationReport.current.missingKeys
            let base = AuthStrings.configurationMessage
            return keys.isEmpty ? base : base + "\n" + AuthStrings.configurationDetails(keys)
        }
    }

    #if DEBUG
        private let previewLinks = LegalLinks.from(webBase: URL(string: "https://app.waivera.test"))

        #Preview("Light") {
            FixturePreview {
                await AuthFixtures.signIn(.empty)
            } content: {
                SignInView(model: $0, legalLinks: previewLinks)
            }
        }
        #Preview("Dark, rejected") {
            FixturePreview {
                await AuthFixtures.signIn(.failed)
            } content: {
                SignInView(model: $0, legalLinks: previewLinks)
            }
            .preferredColorScheme(.dark)
        }
        #Preview("Connecting") {
            FixturePreview {
                await AuthFixtures.signIn(.connecting)
            } content: {
                SignInView(model: $0, legalLinks: previewLinks)
            }
        }
        #Preview("Reset sent") {
            FixturePreview {
                await AuthFixtures.signIn(.resetSent)
            } content: {
                SignInView(model: $0, legalLinks: previewLinks)
            }
        }
        #Preview("Configuration missing") {
            FixturePreview {
                await AuthFixtures.signIn(.configurationMissing)
            } content: {
                SignInView(model: $0)
            }
        }
        #Preview("AX5, invalid") {
            FixturePreview {
                await AuthFixtures.signIn(.invalid)
            } content: {
                SignInView(model: $0, legalLinks: previewLinks)
            }
            .dynamicTypeSize(.accessibility5)
        }
        #Preview("Live fake") { SignInView(legalLinks: previewLinks).fakeDataEnvironment(.signedOut) }
    #endif
#endif
