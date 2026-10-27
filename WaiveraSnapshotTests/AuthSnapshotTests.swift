import AuthFeature
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

/// Every auth screen in every state (`<screen>_<state>`), in light, dark and accessibility XXXL
/// at iPhone SE width, from the same `AuthFixtures` the previews use. A missing reference is
/// recorded and fails once; commit the PNGs from the CI `snapshots` artifact.
@MainActor
final class AuthSnapshotTests: XCTestCase {
    private struct Variant {
        let name: String
        let style: UIUserInterfaceStyle
        let typeSize: DynamicTypeSize
    }

    private let variants = [
        Variant(name: "light", style: .light, typeSize: .large),
        Variant(name: "dark", style: .dark, typeSize: .large),
        Variant(name: "ax5", style: .light, typeSize: .accessibility5),
    ]

    /// iPhone SE (3rd generation) in points.
    private let size = CGSize(width: 375, height: 667)

    private func assertScreen(_ view: some View, named name: String, testName: String = #function) {
        for variant in variants {
            let framed =
                view
                .dynamicTypeSize(variant.typeSize)
                .environment(\.colorScheme, variant.style == .dark ? .dark : .light)
            // Accessibility sizes grow past one screen; snapshot the whole scroll content.
            let layout: SwiftUISnapshotLayout =
                variant.typeSize.isAccessibilitySize
                ? .fixed(width: size.width, height: size.height * 3)
                : .fixed(width: size.width, height: size.height)
            assertSnapshot(
                of: framed,
                as: .image(
                    perceptualPrecision: 0.98,
                    layout: layout,
                    traits: UITraitCollection(userInterfaceStyle: variant.style)
                ),
                named: "\(name)__\(variant.name)",
                testName: testName
            )
        }
    }

    func testSignIn() async {
        for state in AuthFixtures.SignIn.allCases {
            let model = await AuthFixtures.signIn(state)
            assertScreen(SignInView(model: model), named: "sign-in_\(state.rawValue)")
        }
    }

    func testPasswordChangeRequired() async {
        for state in AuthFixtures.PasswordChange.allCases {
            let model = await AuthFixtures.passwordChange(state)
            assertScreen(PasswordChangeRequiredView(model: model) {}, named: "password-change_\(state.rawValue)")
        }
    }

    func testPasswordChangeVoluntary() async {
        for state in [AuthFixtures.PasswordChange.empty, .wrongCurrent, .done] {
            let model = await AuthFixtures.passwordChange(state, mode: .voluntary)
            assertScreen(
                NavigationStack { PasswordChangeView(model: model) {} },
                named: "password-change-voluntary_\(state.rawValue)"
            )
        }
    }

    func testBootstrapFailed() {
        for state in AuthFixtures.Bootstrap.allCases {
            assertScreen(
                BootstrapFailedView(model: AuthFixtures.bootstrap(state)) {},
                named: "bootstrap-failed_\(state.rawValue)"
            )
        }
    }

    func testOnboardingRequired() async {
        for state in AuthFixtures.Onboarding.allCases {
            let model = await AuthFixtures.onboarding(state)
            assertScreen(OnboardingRequiredView(model: model) {}, named: "onboarding-required_\(state.rawValue)")
        }
    }

    func testConfigurationMissing() {
        assertScreen(
            ConfigurationMissingView(report: ConfigurationReport(missingKeys: [])),
            named: "configuration-missing_release"
        )
        assertScreen(
            ConfigurationMissingView(
                report: ConfigurationReport(missingKeys: ["WaiveraAPIBaseURL", "WaiveraFirebaseAPIKey"])
            ),
            named: "configuration-missing_debug"
        )
    }

    func testNotificationPrimer() {
        assertScreen(NotificationPrimerView(onEnable: {}, onNotNow: {}), named: "notification-primer_default")
    }
}
