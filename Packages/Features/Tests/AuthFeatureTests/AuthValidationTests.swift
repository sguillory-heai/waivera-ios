import Testing

@testable import AuthFeature

@Suite("Auth validation")
struct AuthValidationTests {
    @Test func emailIsTrimmedButKeepsItsCase() {
        #expect(AuthValidation.normalizedEmail("  Alex.Rivera@Example.org \n") == "Alex.Rivera@Example.org")
    }

    @Test func emptyOrBlankEmailIsRequired() {
        #expect(AuthValidation.emailIssue("") == .emailRequired)
        #expect(AuthValidation.emailIssue("   ") == .emailRequired)
    }

    @Test(arguments: [
        "alex", "alex@", "@example.org", "alex@example", "alex@@example.org", "al ex@example.org", "alex@example.",
    ])
    func malformedEmailIsInvalid(_ email: String) {
        #expect(AuthValidation.emailIssue(email) == .emailInvalid)
    }

    @Test(arguments: ["alex@example.org", " alex.rivera+waivera@care.example.co.uk "])
    func plausibleEmailPasses(_ email: String) {
        #expect(AuthValidation.emailIssue(email) == nil)
    }

    @Test func signInPasswordIsNeverTrimmed() {
        #expect(AuthValidation.signInPasswordIssue("") == .passwordRequired)
        #expect(AuthValidation.signInPasswordIssue(" ") == nil)
    }

    @Test func newPasswordNeedsEveryRule() {
        let issues = AuthValidation.passwordChangeIssues(current: "old secret", new: "short", confirmation: "short")
        #expect(issues.new == .newPasswordMissingRules)
        #expect(issues.confirmation == nil)
        #expect(!issues.isValid)
    }

    @Test("The rules mirror sprout_api's PasswordPolicy")
    func rulesMirrorTheServerPolicy() {
        #expect(AuthValidation.minimumNewPasswordLength == 12)
        #expect(AuthValidation.unmetPasswordRules("Abcdefghi1!x").isEmpty, "exactly the minimum is allowed")
        #expect(AuthValidation.unmetPasswordRules("Abcdefgh1!x") == [.length])
        #expect(AuthValidation.unmetPasswordRules("abcdefghi1!x") == [.uppercase])
        #expect(AuthValidation.unmetPasswordRules("ABCDEFGHI1!X") == [.lowercase])
        #expect(AuthValidation.unmetPasswordRules("Abcdefghij!x") == [.number])
        #expect(AuthValidation.unmetPasswordRules("Abcdefghij1x") == [.symbol])
        #expect(AuthValidation.unmetPasswordRules("") == Set(PasswordRule.allCases))
    }

    @Test("Only the server's symbols, and ASCII letters and digits, count")
    func onlyTheServersCharactersCount() {
        for symbol in "^$*.[]{}()?\"!@#%&/\\,><':;|_~" {
            #expect(!AuthValidation.unmetPasswordRules("Abcdefghij1\(symbol)").contains(.symbol), "\(symbol)")
        }
        for other in ["-", "+", "=", " ", "`", "€"] {
            #expect(AuthValidation.unmetPasswordRules("Abcdefghij1\(other)").contains(.symbol), "\(other)")
        }
        #expect(AuthValidation.unmetPasswordRules("Ébcdefghij1!").contains(.uppercase), "accented capitals")
        #expect(AuthValidation.unmetPasswordRules("Abcdefghij٣!").contains(.number), "non-ASCII digits")
        #expect(AuthValidation.unmetPasswordRules("Abcdefghi1!👍").isEmpty, "an emoji counts as two, like the server")
    }

    @Test func newPasswordMustDifferFromTheCurrentOne() {
        let issues = AuthValidation.passwordChangeIssues(
            current: "Same_phrase42",
            new: "Same_phrase42",
            confirmation: "Same_phrase42"
        )
        #expect(issues.new == .newPasswordSameAsCurrent)
    }

    @Test func everyProblemIsReportedAtOnce() {
        let issues = AuthValidation.passwordChangeIssues(current: "", new: "Long_enough42", confirmation: "other")
        #expect(issues.current == .currentPasswordRequired)
        #expect(issues.new == nil)
        #expect(issues.confirmation == .confirmationMismatch)
    }

    @Test func validChangePasses() {
        let issues = AuthValidation.passwordChangeIssues(
            current: "old secret",
            new: "Brand_new_phrase7",
            confirmation: "Brand_new_phrase7"
        )
        #expect(issues.isValid)
    }
}
