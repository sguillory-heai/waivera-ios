import Foundation

/// One line of the new-password checklist with its copy already built, so the view only lays it out.
public struct PasswordRuleLine: Identifiable, Equatable, Sendable {
    public let rule: PasswordRule
    public let isMet: Bool
    public let label: String
    /// What VoiceOver reads: the rule and whether it is met.
    public let spokenLabel: String

    public var id: PasswordRule { rule }

    /// Every rule, in the server's order, ticked off against `unmet`.
    static func lines(unmet: Set<PasswordRule>) -> [PasswordRuleLine] {
        PasswordRule.allCases.map { rule in
            let isMet = !unmet.contains(rule)
            return PasswordRuleLine(
                rule: rule,
                isMet: isMet,
                label: AuthStrings.passwordRule(rule),
                spokenLabel: AuthStrings.passwordRuleSpoken(rule, met: isMet)
            )
        }
    }
}
