import SwiftUI
import WaiveraDesign

/// Email and password sign-in. The auth agent fills this in; the app shows it whenever the
/// session is signed out and moves on by itself when the session changes.
public struct SignInView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder(title: AuthStrings.signInTitle, systemImage: "person.badge.key")
            .accessibilityIdentifier("screen.sign-in")
    }
}

/// Shown when the backend says the password must change before the app can be used.
public struct PasswordChangeRequiredView: View {
    private let onSignOut: () -> Void

    public init(onSignOut: @escaping () -> Void) {
        self.onSignOut = onSignOut
    }

    public var body: some View {
        GateMessage(
            systemImage: "key.fill",
            title: AuthStrings.passwordChangeTitle,
            message: AuthStrings.passwordChangeMessage,
            onSignOut: onSignOut
        )
        .accessibilityIdentifier("screen.password-change")
    }
}

/// Shown when the account has not finished onboarding on the web.
public struct OnboardingRequiredView: View {
    private let onSignOut: () -> Void

    public init(onSignOut: @escaping () -> Void) {
        self.onSignOut = onSignOut
    }

    public var body: some View {
        GateMessage(
            systemImage: "list.bullet.clipboard",
            title: AuthStrings.onboardingTitle,
            message: AuthStrings.onboardingMessage,
            onSignOut: onSignOut
        )
        .accessibilityIdentifier("screen.onboarding-required")
    }
}

private struct GateMessage: View {
    let systemImage: String
    let title: String
    let message: String
    let onSignOut: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.large) {
                EmptyStateView(systemImage: systemImage, title: title, message: message)
                WaiveraButton(AuthStrings.signOut, variant: .secondary, action: onSignOut)
                    .padding(.horizontal, Spacing.medium)
            }
            .padding(.vertical, Spacing.extraLarge)
        }
        .background(Palette.background)
    }
}

#Preview("Light") { PasswordChangeRequiredView {} }
#Preview("Dark") { OnboardingRequiredView {}.preferredColorScheme(.dark) }
#Preview("AX XXXL") { PasswordChangeRequiredView {}.dynamicTypeSize(.accessibility5) }
