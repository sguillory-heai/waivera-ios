import Foundation
import WaiveraAPI

/// User-facing copy for the auth screens, from `Localizable.strings` in this module. Foundation
/// only (`NSLocalizedString`), so the models and their copy are tested on Linux too.
enum AuthStrings {
    // MARK: Sign in
    static var brand: String { text("auth.brand") }
    static var signInTitle: String { text("auth.signIn.title") }
    static var emailLabel: String { text("auth.field.email") }
    static var emailPlaceholder: String { text("auth.field.email.placeholder") }
    static var passwordLabel: String { text("auth.field.password") }
    static var passwordPlaceholder: String { text("auth.field.password.placeholder") }
    static var signInButton: String { text("auth.signIn.button") }
    static var connecting: String { text("auth.signIn.connecting") }
    static var forgotPassword: String { text("auth.signIn.forgotPassword") }
    static var resetSending: String { text("auth.signIn.resetSending") }
    static var signInFailedTitle: String { text("auth.signIn.failed.title") }
    static var resetSentTitle: String { text("auth.signIn.resetSent.title") }
    /// The reset confirmation, with the address on a line of its own so it never breaks at its dots.
    static func resetSentMessage(_ email: String) -> String { text("auth.signIn.resetSent.message") + "\n" + email }
    static var linkFailedTitle: String { text("auth.signIn.linkFailed.title") }
    static var linkFailedMessage: String { text("auth.signIn.linkFailed.message") }
    static var legalLead: String { text("auth.legal.lead") }
    static var legalTermsLead: String { text("auth.legal.termsLead") }
    static var legalTerms: String { text("auth.legal.terms") }
    static var legalAnd: String { text("auth.legal.and") }
    static var legalPrivacy: String { text("auth.legal.privacy") }
    static var legalEnd: String { text("auth.legal.end") }
    static var legalOpenHint: String { text("auth.legal.openHint") }
    /// The whole legal sentence, as VoiceOver reads the footer.
    static var legalSentence: String {
        [legalLead, legalTermsLead, legalTerms, legalAnd, legalPrivacy].joined(separator: " ") + legalEnd
    }
    static var configurationTitle: String { text("auth.configuration.title") }
    static var configurationMessage: String { text("auth.configuration.message") }
    static func configurationDetails(_ keys: [String]) -> String {
        format("auth.configuration.details", keys.joined(separator: ", "))
    }

    // MARK: Validation
    static func issue(_ issue: AuthFieldIssue) -> String {
        switch issue {
        case .emailRequired: text("auth.issue.emailRequired")
        case .emailInvalid: text("auth.issue.emailInvalid")
        case .passwordRequired: text("auth.issue.passwordRequired")
        case .currentPasswordRequired: text("auth.issue.currentRequired")
        case .currentPasswordWrong: text("auth.issue.currentWrong")
        case .newPasswordTooShort(let minimum): format("auth.issue.newTooShort", minimum)
        case .newPasswordSameAsCurrent: text("auth.issue.newSame")
        case .newPasswordWeak: text("auth.issue.newWeak")
        case .confirmationMismatch: text("auth.issue.confirmMismatch")
        }
    }

    /// Copy for a failure, never provider or server text (01 §3, G-12).
    static func failure(_ error: WaiveraError) -> String {
        error.userMessage
    }

    // MARK: Password change
    static var passwordChangeTitle: String { text("auth.passwordChange.title") }
    static var passwordChangeRequiredTitle: String { text("auth.passwordChange.required.title") }
    static var passwordChangeRequiredMessage: String { text("auth.passwordChange.required.message") }
    static var passwordChangeVoluntaryMessage: String { text("auth.passwordChange.voluntary.message") }
    static var currentPasswordLabel: String { text("auth.field.currentPassword") }
    static var currentPasswordPlaceholder: String { text("auth.field.currentPassword.placeholder") }
    static var newPasswordLabel: String { text("auth.field.newPassword") }
    static var newPasswordPlaceholder: String { text("auth.field.newPassword.placeholder") }
    static var newPasswordHint: String {
        format("auth.field.newPassword.hint", AuthValidation.minimumNewPasswordLength)
    }
    static var confirmPasswordLabel: String { text("auth.field.confirmPassword") }
    static var confirmPasswordPlaceholder: String { text("auth.field.confirmPassword.placeholder") }
    static var passwordChangeSave: String { text("auth.passwordChange.save") }
    static var passwordChangeSaving: String { text("auth.passwordChange.saving") }
    static var passwordChangeFailedTitle: String { text("auth.passwordChange.failed.title") }
    static var passwordChangeDoneTitle: String { text("auth.passwordChange.done.title") }
    static var passwordChangeDoneMessage: String { text("auth.passwordChange.done.message") }
    static var signOut: String { text("auth.signOut") }

    // MARK: Gates
    static var onboardingTitle: String { text("auth.onboarding.title") }
    static var onboardingMessage: String { text("auth.onboarding.message") }
    static var onboardingHelp: String { text("auth.onboarding.help") }
    static var onboardingCheck: String { text("auth.onboarding.check") }
    static var onboardingChecking: String { text("auth.onboarding.checking") }
    static var onboardingStillPending: String { text("auth.onboarding.stillPending") }
    static var bootstrapFailedTitle: String { text("auth.bootstrapFailed.title") }
    static var bootstrapOfflineTitle: String { text("auth.bootstrapFailed.offline.title") }
    static var bootstrapOfflineMessage: String { text("auth.bootstrapFailed.offline.message") }
    static var bootstrapHelp: String { text("auth.bootstrapFailed.help") }
    static var bootstrapStillFailingTitle: String { text("auth.bootstrapFailed.stillFailing.title") }
    /// `time` is the last attempt's local time of day, already formatted.
    static func bootstrapStillFailingMessage(_ time: String) -> String {
        format("auth.bootstrapFailed.stillFailing.message", time)
    }
    static var tryAgain: String { text("auth.tryAgain") }
    static var retrying: String { text("auth.retrying") }

    // MARK: Notification primer
    static var primerTitle: String { text("auth.primer.title") }
    static var primerMessage: String { text("auth.primer.message") }
    static var primerMessagesTitle: String { text("auth.primer.messages.title") }
    static var primerMessagesBody: String { text("auth.primer.messages.body") }
    static var primerScheduleTitle: String { text("auth.primer.schedule.title") }
    static var primerScheduleBody: String { text("auth.primer.schedule.body") }
    static var primerGroupTitle: String { text("auth.primer.group.title") }
    static var primerGroupBody: String { text("auth.primer.group.body") }
    static var primerRemindersTitle: String { text("auth.primer.reminders.title") }
    static var primerRemindersBody: String { text("auth.primer.reminders.body") }
    static var primerChangesTitle: String { text("auth.primer.changes.title") }
    static var primerChangesBody: String { text("auth.primer.changes.body") }
    static var primerDigestTitle: String { text("auth.primer.digest.title") }
    static var primerDigestBody: String { text("auth.primer.digest.body") }
    static var primerFootnote: String { text("auth.primer.footnote") }
    static var primerEnable: String { text("auth.primer.enable") }
    static var primerRequesting: String { text("auth.primer.requesting") }
    static var primerNotNow: String { text("auth.primer.notNow") }
    static var primerSampleApp: String { text("auth.primer.sample.app") }
    static var primerSampleSender: String { text("auth.primer.sample.sender") }
    static var primerSampleBody: String { text("auth.primer.sample.body") }
    static var primerSampleAccessibility: String { text("auth.primer.sample.accessibility") }

    private static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    private static func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: text(key), arguments: arguments)
    }
}
