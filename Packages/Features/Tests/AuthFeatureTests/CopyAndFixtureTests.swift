import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import AuthFeature

@Suite("Auth copy")
struct AuthCopyTests {
    private static let issues: [AuthFieldIssue] = [
        .emailRequired, .emailInvalid, .passwordRequired, .currentPasswordRequired, .currentPasswordWrong,
        .newPasswordTooShort(minimum: 8), .newPasswordSameAsCurrent, .newPasswordWeak, .confirmationMismatch,
    ]

    @Test func everyIssueHasCopy() {
        for issue in Self.issues {
            let text = AuthStrings.issue(issue)
            #expect(!text.isEmpty)
            #expect(!text.hasPrefix("auth."), "missing string for \(issue)")
        }
        #expect(AuthStrings.issue(.newPasswordTooShort(minimum: 8)) == "Use at least 8 characters.")
        #expect(AuthStrings.newPasswordHint.contains("8"))
    }

    @Test func resetMessageNamesTheAddressOnItsOwnLine() {
        let message = AuthStrings.resetSentMessage("alex@example.org")
        #expect(message.hasSuffix("\nalex@example.org"))
        #expect(!message.hasPrefix("auth."))
    }

    @Test func signInCarriesNoFillerCopy() {
        // Everything on sign-in helps someone sign in: a title, the fields, the actions and the
        // legal sentence, and nothing else (as on Android).
        #expect(AuthStrings.signInTitle == "Welcome back")
        #expect(
            AuthStrings.legalSentence
                == "By continuing, you agree to our Terms of Service and Privacy Policy."
        )
        for text in [
            AuthStrings.signInFailedTitle, AuthStrings.resetSentTitle, AuthStrings.linkFailedTitle,
            AuthStrings.linkFailedMessage, AuthStrings.passwordPlaceholder, AuthStrings.legalOpenHint,
        ] {
            #expect(!text.isEmpty)
            #expect(!text.hasPrefix("auth."))
        }
    }

    @Test func screenCopyIsUserFacing() {
        // The Expo gates shipped developer notes; none of that copy may return (01 §5).
        let texts = [
            AuthStrings.passwordChangeRequiredMessage, AuthStrings.onboardingMessage,
            AuthStrings.configurationMessage, AuthStrings.bootstrapHelp,
        ]
        for text in texts {
            #expect(!text.hasPrefix("auth."))
            #expect(!text.contains("PRD"))
            #expect(!text.contains("DTO"))
            #expect(!text.contains("xcconfig"))
        }
    }

    @Test func primerExplainsEveryCategoryByMeaning() {
        #expect(
            PrimerCategory.allCases.map(\.rawValue) == [
                "messages", "group_activity", "schedule_reminders", "schedule_changes", "digest",
            ]
        )
        for category in PrimerCategory.allCases {
            #expect(!category.title.hasPrefix("auth."))
            #expect(!category.detail.hasPrefix("auth."))
        }
    }

    @Test func primerGroupsTheCategoriesIntoThreeKinds() {
        #expect(PrimerKind.allCases == [.messages, .schedule, .digest])
        let grouped = PrimerKind.allCases.flatMap(\.categories)
        #expect(grouped == PrimerCategory.allCases, "every category is explained once, in order")
        #expect(PrimerKind.messages.tone == .brand)
        #expect(PrimerKind.schedule.tone == .teal)
        #expect(PrimerKind.digest.tone == .amber)
        for kind in PrimerKind.allCases {
            #expect(!kind.title.hasPrefix("auth."))
            #expect(!kind.detail.hasPrefix("auth."))
        }
    }
}

@MainActor
@Suite("Auth fixtures")
struct AuthFixtureTests {
    /// The previews and snapshots render these; each must really be in the state it names.
    @Test func signInFixtures() async {
        #expect(await AuthFixtures.signIn(.empty).canSubmit == false)
        #expect(await AuthFixtures.signIn(.filled).canSubmit)
        #expect(await AuthFixtures.signIn(.invalid).emailIssue == .emailInvalid)
        #expect(await AuthFixtures.signIn(.failed).notice == .failed(.auth(.invalidCredentials)))
        #expect(await AuthFixtures.signIn(.unauthorized).notice == .failed(.unauthorized))
        #expect(await AuthFixtures.signIn(.connecting).isConnecting)
        #expect(await AuthFixtures.signIn(.resetSent).notice == .resetSent(email: AuthFixtures.email))
        #expect(await AuthFixtures.signIn(.configurationMissing).isConfigured == false)
    }

    @Test func passwordChangeFixtures() async {
        #expect(await AuthFixtures.passwordChange(.empty).phase == .editing)
        #expect(await AuthFixtures.passwordChange(.invalid).issues.new != nil)
        #expect(await AuthFixtures.passwordChange(.wrongCurrent).issues.current == .currentPasswordWrong)
        #expect(await AuthFixtures.passwordChange(.offline).error == .offline)
        #expect(await AuthFixtures.passwordChange(.saving).isSaving)
        #expect(await AuthFixtures.passwordChange(.done).phase == .done)
    }

    @Test func gateFixtures() async {
        #expect(AuthFixtures.bootstrap(.server).error == .server(statusCode: 503))
        #expect(AuthFixtures.bootstrap(.offline).isOffline)
        #expect(AuthFixtures.bootstrap(.retrying).isRetrying)
        #expect(await AuthFixtures.onboarding(.waiting).status == .waiting)
        #expect(await AuthFixtures.onboarding(.checking).isChecking)
        #expect(await AuthFixtures.onboarding(.stillPending).status == .stillPending)
        #expect(await AuthFixtures.onboarding(.failed).status == .failed(.offline))
    }
}
