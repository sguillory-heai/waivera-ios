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
        let model: BootstrapFailedModel
        let fallbackMessage: String
        let onSignOut: () -> Void

        var body: some View {
            AuthScaffold {
                AuthHeader(
                    systemImage: model.isOffline ? "wifi.slash" : "exclamationmark.icloud.fill",
                    title: model.isOffline ? AuthStrings.bootstrapOfflineTitle : AuthStrings.bootstrapFailedTitle,
                    message: model.error.map(AuthStrings.failure) ?? fallbackMessage,
                    tone: model.isOffline ? .amber : .danger
                )
                Text(AuthStrings.bootstrapHelp)
                    .font(WaiveraFont.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Spacing.small) {
                    WaiveraButton(AuthStrings.tryAgain, isLoading: model.isRetrying, action: { model.retry() })
                        .accessibilityIdentifier("state.action")
                    WaiveraButton(AuthStrings.signOut, variant: .secondary, action: onSignOut)
                        .disabled(model.isRetrying)
                        .accessibilityIdentifier("bootstrap.signOut")
                }
            }
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
                        .font(WaiveraFont.caption)
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
        let model: OnboardingModel
        let onSignOut: () -> Void

        var body: some View {
            AuthScaffold {
                AuthHeader(
                    systemImage: "list.bullet.clipboard.fill",
                    title: AuthStrings.onboardingTitle,
                    message: AuthStrings.onboardingMessage
                )
                Text(AuthStrings.onboardingHelp)
                    .font(WaiveraFont.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                switch model.status {
                case .stillPending:
                    BannerView(.info, message: AuthStrings.onboardingStillPending)
                        .authNoticeTransition()
                        .accessibilityIdentifier("onboarding.stillPending")
                case .failed(let error):
                    BannerView(.error, message: AuthStrings.failure(error))
                        .authNoticeTransition()
                        .accessibilityIdentifier("onboarding.error")
                case .waiting, .checking:
                    EmptyView()
                }
                VStack(spacing: Spacing.small) {
                    WaiveraButton(AuthStrings.onboardingCheck, isLoading: model.isChecking, action: { checkAgain() })
                        .disabled(!model.canCheck && !model.isChecking)
                        .accessibilityIdentifier("onboarding.check")
                    WaiveraButton(AuthStrings.signOut, variant: .secondary, action: onSignOut)
                        .disabled(model.isChecking)
                        .accessibilityIdentifier("onboarding.signOut")
                }
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
        #Preview("Bootstrap retrying, AX XXXL") {
            BootstrapFailedView(model: AuthFixtures.bootstrap(.retrying)) {}.dynamicTypeSize(.accessibility5)
        }
        #Preview("Configuration missing") {
            ConfigurationMissingView(report: ConfigurationReport(missingKeys: ["WaiveraAPIBaseURL"]))
        }
        #Preview("Configuration missing, dark") {
            ConfigurationMissingView(report: ConfigurationReport(missingKeys: [])).preferredColorScheme(.dark)
        }
        #Preview("Configuration missing, AX XXXL") {
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
        #Preview("Onboarding failed, AX XXXL") {
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
