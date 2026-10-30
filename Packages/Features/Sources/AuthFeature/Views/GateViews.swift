#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Firebase is signed in but the backend login failed for a reason other than 401/403 (01 §2).
    /// Try again runs the backend login again without signing out; Sign out returns to sign-in.
    public struct BootstrapFailedView: View {
        @Environment(\.dataEnvironment) private var data
        private let injected: BootstrapFailedModel?
        private let message: String
        private let onRetry: () -> Void
        private let onSignOut: () -> Void

        /// `message` is a `WaiveraError.userMessage`, never server text.
        public init(message: String, onRetry: @escaping () -> Void, onSignOut: @escaping () -> Void) {
            injected = nil
            self.message = message
            self.onRetry = onRetry
            self.onSignOut = onSignOut
        }

        /// For previews and snapshot tests.
        public init(model: BootstrapFailedModel, onSignOut: @escaping () -> Void) {
            injected = model
            message = model.error?.userMessage ?? WaiveraError.invalidResponse.userMessage
            onRetry = {}
            self.onSignOut = onSignOut
        }

        public var body: some View {
            Group {
                if let injected {
                    BootstrapFailedContent(model: injected, fallbackMessage: message, onSignOut: onSignOut)
                } else {
                    BootstrapFailedHost(
                        session: data?.session,
                        message: message,
                        onRetry: onRetry,
                        onSignOut: onSignOut
                    )
                }
            }
            .accessibilityIdentifier("screen.bootstrap-failed")
        }
    }

    private struct BootstrapFailedHost: View {
        @State private var model: BootstrapFailedModel
        let message: String
        let onSignOut: () -> Void

        init(
            session: (any SessionRepository)?,
            message: String,
            onRetry: @escaping () -> Void,
            onSignOut: @escaping () -> Void
        ) {
            _model = State(initialValue: BootstrapFailedModel(session: session, onRetry: onRetry))
            self.message = message
            self.onSignOut = onSignOut
        }

        var body: some View {
            BootstrapFailedContent(model: model, fallbackMessage: message, onSignOut: onSignOut)
                .task { await model.observeSession() }
        }
    }

    private struct BootstrapFailedContent: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let model: BootstrapFailedModel
        let fallbackMessage: String
        let onSignOut: () -> Void

        var body: some View {
            // At large text Try again stays pinned and Sign out moves to the end of the content,
            // so no action is ever cut in half at the fold (UI11-05).
            let signOutInline = dynamicTypeSize.isLargeText
            AuthScaffold(pinnedAtLargeText: true) {
                AuthHeader(
                    systemImage: model.isOffline ? "icloud.slash" : "exclamationmark.triangle.fill",
                    title: model.isOffline ? AuthStrings.bootstrapOfflineTitle : AuthStrings.bootstrapFailedTitle,
                    // The title already says "offline"; the body says what to do instead.
                    message: model.isOffline
                        ? AuthStrings.bootstrapOfflineMessage
                        : (model.error.map(AuthStrings.failure) ?? fallbackMessage),
                    tone: model.isOffline ? .neutral : .danger
                )
                if let failedAt = model.lastFailedRetryAt, !model.isRetrying {
                    BannerView(
                        .warning,
                        title: AuthStrings.bootstrapStillFailingTitle,
                        message: AuthStrings.bootstrapStillFailingMessage(
                            failedAt.formatted(date: .omitted, time: .shortened)
                        )
                    )
                    .authNoticeTransition()
                    .accessibilityIdentifier("bootstrap.stillFailing")
                }
                AuthHelp(text: AuthStrings.bootstrapHelp)
                if signOutInline {
                    GateSignOut(isEnabled: !model.isRetrying, action: onSignOut)
                        .accessibilityIdentifier("bootstrap.signOut")
                }
            } actions: {
                GateActions(
                    title: AuthStrings.tryAgain,
                    busyTitle: AuthStrings.retrying,
                    isBusy: model.isRetrying,
                    onPrimary: { model.retry() },
                    onSignOut: signOutInline ? nil : onSignOut
                )
            }
            .waiveraAnimation(.layout, value: model.lastFailedRetryAt)
        }
    }

    /// The build has no API base URL or Firebase key, so nothing can sign in (01 §3). DEBUG builds
    /// also list the missing setting names (never values) for whoever is setting the build up.
    public struct ConfigurationMissingView: View {
        private let report: ConfigurationReport

        public init() {
            report = .current
        }

        /// For previews and snapshot tests.
        public init(report: ConfigurationReport) {
            self.report = report
        }

        public var body: some View {
            AuthScaffold {
                AuthHeader(
                    systemImage: "wrench.and.screwdriver.fill",
                    title: AuthStrings.configurationTitle,
                    message: AuthStrings.configurationMessage,
                    tone: .amber
                )
                if !report.missingKeys.isEmpty {
                    Text(AuthStrings.configurationDetails(report.missingKeys))
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("configuration.details")
                }
            }
            .accessibilityIdentifier("screen.configuration-missing")
        }
    }

    /// Shown when the account has not finished onboarding (01 §5). There is no onboarding
    /// contract, so the person finishes elsewhere, then checks again or signs out.
    public struct OnboardingRequiredView: View {
        @Environment(\.dataEnvironment) private var data
        private let injected: OnboardingModel?
        private let onSignOut: () -> Void

        public init(onSignOut: @escaping () -> Void) {
            injected = nil
            self.onSignOut = onSignOut
        }

        /// For previews and snapshot tests.
        public init(model: OnboardingModel, onSignOut: @escaping () -> Void) {
            injected = model
            self.onSignOut = onSignOut
        }

        public var body: some View {
            Group {
                if let injected {
                    OnboardingContent(model: injected, onSignOut: onSignOut)
                } else {
                    OnboardingHost(session: data?.session, onSignOut: onSignOut)
                }
            }
            .accessibilityIdentifier("screen.onboarding-required")
        }
    }

    private struct OnboardingHost: View {
        @State private var model: OnboardingModel
        let onSignOut: () -> Void

        init(session: (any SessionRepository)?, onSignOut: @escaping () -> Void) {
            _model = State(initialValue: OnboardingModel(session: session))
            self.onSignOut = onSignOut
        }

        var body: some View {
            OnboardingContent(model: model, onSignOut: onSignOut)
                .task { await model.observeSession() }
        }
    }

    private struct OnboardingContent: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let model: OnboardingModel
        let onSignOut: () -> Void

        var body: some View {
            // At large text the main action stays pinned, so "Checking…" is always in sight on a
            // small phone, and Sign out moves to the end of the content (UI8-07).
            let signOutInline = dynamicTypeSize.isLargeText
            AuthScaffold(pinnedAtLargeText: true) {
                AuthHeader(
                    systemImage: "person.fill",
                    title: AuthStrings.onboardingTitle,
                    message: AuthStrings.onboardingMessage,
                    welcome: true
                )
                switch model.status {
                case .stillPending:
                    BannerView(.warning, message: AuthStrings.onboardingStillPending)
                        .authNoticeTransition()
                        .accessibilityIdentifier("onboarding.stillPending")
                case .failed(let error):
                    BannerView(.error, message: AuthStrings.failure(error))
                        .authNoticeTransition()
                        .accessibilityIdentifier("onboarding.error")
                case .waiting, .checking:
                    EmptyView()
                }
                AuthHelp(text: AuthStrings.onboardingHelp)
                if signOutInline {
                    GateSignOut(isEnabled: !model.isChecking, action: onSignOut)
                        .accessibilityIdentifier("onboarding.signOut")
                }
            } actions: {
                GateActions(
                    title: AuthStrings.onboardingCheck,
                    busyTitle: AuthStrings.onboardingChecking,
                    isBusy: model.isChecking,
                    isEnabled: model.canCheck,
                    onPrimary: { checkAgain() },
                    onSignOut: signOutInline ? nil : onSignOut,
                    identifier: "onboarding.check"
                )
            }
            .waiveraAnimation(.layout, value: model.status)
        }

        private func checkAgain() {
            Task { await model.checkAgain() }
        }
    }

    #if DEBUG
        #Preview("Bootstrap failed") {
            BootstrapFailedView(model: AuthFixtures.bootstrap(.server)) {}
        }
        #Preview("Bootstrap offline, dark") {
            BootstrapFailedView(model: AuthFixtures.bootstrap(.offline)) {}.preferredColorScheme(.dark)
        }
        #Preview("Bootstrap retrying, AX5") {
            BootstrapFailedView(model: AuthFixtures.bootstrap(.retrying)) {}.dynamicTypeSize(.accessibility5)
        }
        #Preview("Configuration missing") {
            ConfigurationMissingView(report: ConfigurationReport(missingKeys: ["WaiveraAPIBaseURL"]))
        }
        #Preview("Configuration missing, dark") {
            ConfigurationMissingView(report: ConfigurationReport(missingKeys: [])).preferredColorScheme(.dark)
        }
        #Preview("Configuration missing, AX5") {
            ConfigurationMissingView(report: ConfigurationReport(missingKeys: ["WaiveraFirebaseAPIKey"]))
                .dynamicTypeSize(.accessibility5)
        }
        #Preview("Onboarding") {
            FixturePreview {
                await AuthFixtures.onboarding(.waiting)
            } content: {
                OnboardingRequiredView(model: $0) {}
            }
        }
        #Preview("Onboarding still pending, dark") {
            FixturePreview {
                await AuthFixtures.onboarding(.stillPending)
            } content: {
                OnboardingRequiredView(model: $0) {}
            }
            .preferredColorScheme(.dark)
        }
        #Preview("Onboarding failed, AX5") {
            FixturePreview {
                await AuthFixtures.onboarding(.failed)
            } content: {
                OnboardingRequiredView(model: $0) {}
            }
            .dynamicTypeSize(.accessibility5)
        }
        #Preview("Live fake") { OnboardingRequiredView {}.fakeDataEnvironment() }
    #endif
#endif
