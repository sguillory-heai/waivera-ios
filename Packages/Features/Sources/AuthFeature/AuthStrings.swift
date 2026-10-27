import Foundation

enum AuthStrings {
    static var signInTitle: String { String(localized: "auth.signIn.title", bundle: .module) }
    static var signOut: String { String(localized: "auth.signOut", bundle: .module) }
    static var passwordChangeTitle: String { String(localized: "auth.passwordChange.title", bundle: .module) }
    static var passwordChangeMessage: String { String(localized: "auth.passwordChange.message", bundle: .module) }
    static var onboardingTitle: String { String(localized: "auth.onboarding.title", bundle: .module) }
    static var onboardingMessage: String { String(localized: "auth.onboarding.message", bundle: .module) }
    static var primerTitle: String { String(localized: "auth.primer.title", bundle: .module) }
    static var primerMessages: String { String(localized: "auth.primer.messages", bundle: .module) }
    static var primerAssignments: String { String(localized: "auth.primer.assignments", bundle: .module) }
    static var primerSchedule: String { String(localized: "auth.primer.schedule", bundle: .module) }
    static var primerFootnote: String { String(localized: "auth.primer.footnote", bundle: .module) }
    static var primerEnable: String { String(localized: "auth.primer.enable", bundle: .module) }
    static var primerNotNow: String { String(localized: "auth.primer.notNow", bundle: .module) }
    static var primerSampleSender: String { String(localized: "auth.primer.sample.sender", bundle: .module) }
    static var primerSampleBody: String { String(localized: "auth.primer.sample.body", bundle: .module) }
    static var primerSampleAccessibility: String {
        String(localized: "auth.primer.sample.accessibility", bundle: .module)
    }
}
