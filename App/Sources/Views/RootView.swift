import AuthFeature
import SwiftUI
import WaiveraDesign

/// Auth gate: renders the gate screen for the session state, or the tab shell once signed in.
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .preferredColorScheme(model.colorScheme)
            .environment(\.waiveraHapticsEnabled, model.preferences.hapticsEnabled)
            .tint(Palette.accent)
            .onOpenURL { url in model.handle(url: url) }
            .onChange(of: scenePhase) { _, phase in
                model.scenePhaseChanged(isActive: phase == .active)
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
