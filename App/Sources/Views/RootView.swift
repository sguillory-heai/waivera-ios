import AuthFeature
import SwiftUI
import WaiveraData
import WaiveraDesign
import WaiveraRouting

/// Auth gate: renders the gate screen for the session state, or the tab shell once signed in.
/// Injects the data layer for every feature screen below it.
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .overlay { if hidesContent { PrivacyCover() } }
            .environment(\.openURL, OpenURLAction(handler: open))
            .environment(\.dataEnvironment, model.dataEnvironment)
            .preferredColorScheme(model.colorScheme)
            .environment(\.waiveraHapticsEnabled, model.settings.hapticsEnabled)
            .tint(Palette.accent)
            .onOpenURL { url in model.handle(url: url) }
            .onChange(of: scenePhase, initial: true) { _, phase in
                model.scenePhaseChanged(to: phase)
            }
    }

    /// Chats and colleagues' details stay out of the app switcher snapshot (AS-09): the cover
    /// goes up as soon as the scene stops being active, before the system takes the snapshot.
    private var hidesContent: Bool {
        scenePhase != .active && model.session.isSignedIn
    }

    /// Every `openURL` in the app passes through here (AS-04): app links navigate, web links go
    /// to the browser, every other scheme is dropped.
    private func open(_ url: URL) -> OpenURLAction.Result {
        switch LinkPolicy.decide(url) {
        case .navigate:
            model.handle(url: url)
            return .handled
        case .browser:
            return .systemAction
        case .blocked:
            return .discarded
        }
    }

    @ViewBuilder private var content: some View {
        switch model.gate {
        case .loading:
            LoadingStateView(caption: AppStrings.loading)
                .background(Palette.background)
                .accessibilityIdentifier("screen.loading")
        case .signIn:
            SignInView()
        case .bootstrapFailed:
            BootstrapFailedView(
                message: model.bootstrapFailureMessage,
                onRetry: { model.retryBootstrap() },
                onSignOut: { model.signOut() }
            )
        case .configurationMissing:
            ConfigurationMissingView()
        case .passwordChange:
            PasswordChangeRequiredView { model.signOut() }
        case .onboardingRequired:
            OnboardingRequiredView { model.signOut() }
        case .notificationPrimer:
            NotificationPrimerView(
                onEnable: { model.choosePrimer(.enable) },
                onNotNow: { model.choosePrimer(.notNow) }
            )
        case nil:
            MainTabView(model: model)
        }
    }
}
