import AuthFeature
import SwiftUI
import WaiveraData
import WaiveraDesign

/// Auth gate: renders the gate screen for the session state, or the tab shell once signed in.
/// Injects the data layer for every feature screen below it.
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .environment(\.dataEnvironment, model.dataEnvironment)
            .preferredColorScheme(model.colorScheme)
            .environment(\.waiveraHapticsEnabled, model.settings.hapticsEnabled)
            .tint(Palette.accent)
            .onOpenURL { url in model.handle(url: url) }
            .onChange(of: scenePhase, initial: true) { _, phase in
                model.scenePhaseChanged(to: phase)
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
