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

    @Test func newPasswordNeedsTheMinimumLength() {
        let issues = AuthValidation.passwordChangeIssues(current: "old secret", new: "short", confirmation: "short")
        #expect(issues.new == .newPasswordTooShort(minimum: 8))
        #expect(issues.confirmation == nil)
        #expect(!issues.isValid)
    }

    @Test func newPasswordMustDifferFromTheCurrentOne() {
        let issues = AuthValidation.passwordChangeIssues(
            current: "same phrase here",
            new: "same phrase here",
            confirmation: "same phrase here"
        )
        #expect(issues.new == .newPasswordSameAsCurrent)
    }

    @Test func everyProblemIsReportedAtOnce() {
        let issues = AuthValidation.passwordChangeIssues(current: "", new: "long enough phrase", confirmation: "other")
        #expect(issues.current == .currentPasswordRequired)
        #expect(issues.new == nil)
        #expect(issues.confirmation == .confirmationMismatch)
    }

    @Test func validChangePasses() {
        let issues = AuthValidation.passwordChangeIssues(
            current: "old secret",
            new: "a brand new phrase",
            confirmation: "a brand new phrase"
        )
        #expect(issues.isValid)
    }
}
