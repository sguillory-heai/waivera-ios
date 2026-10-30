import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import AuthFeature

@MainActor
@Suite("Sign-in model")
struct SignInModelTests {
    private let email = "alex.rivera@example.org"

    private func filled(_ session: ScriptedSession, password: String = "correct horse") -> SignInModel {
        let model = SignInModel(session: session)
        model.setEmail(email)
        model.setPassword(password)
        return model
    }

    // MARK: Idle and enablement

    @Test func buttonNeedsBothFields() {
        let model = SignInModel(session: ScriptedSession())
        #expect(model.fieldsEnabled)
        #expect(!model.canSubmit)
        model.setEmail("   ")
        model.setPassword("x")
        #expect(!model.canSubmit, "a blank email does not count (01 §3)")
        model.setEmail(email)
        #expect(model.canSubmit)
    }

    // MARK: Validation

    @Test func invalidFieldsAreExplainedAndNothingIsSent() async {
        let session = ScriptedSession()
        let model = SignInModel(session: session)
        model.setEmail("alex.rivera")
        await model.submit()
        #expect(model.emailIssue == .emailInvalid)
        #expect(model.passwordIssue == .passwordRequired)
        #expect(model.failureCount == 1)
        #expect(model.rejectionCount == 0, "a field error never vibrates")
        #expect(session.calls.isEmpty)
    }

    @Test func editingAFieldClearsItsIssueAndTheNotice() async {
        let session = ScriptedSession()
        session.signInOutcome.set(.fail(.auth(.invalidCredentials)))
        let model = filled(session)
        await model.submit()
        #expect(model.notice == .failed(.auth(.invalidCredentials)))
        model.setPassword("another try")
        #expect(model.notice == nil)
        model.setEmail("x")
        await model.submit()
        #expect(model.emailIssue == .emailInvalid)
        model.setEmail(email)
        #expect(model.emailIssue == nil)
    }

    // MARK: Submit

    @Test func submitTrimsTheEmailButNotThePassword() async {
        let session = ScriptedSession()
        let model = SignInModel(session: session)
        model.setEmail("  \(email)  ")
        model.setPassword(" pass word ")
        await model.submit()
        #expect(session.calls == ["signIn:\(email): pass word "])
    }

    @Test func credentialErrorIsMappedAndKeepsTheFields() async {
        let session = ScriptedSession()
        session.signInOutcome.set(.fail(.auth(.invalidCredentials)))
        let model = filled(session, password: "wrong")
        await model.submit()
        #expect(model.phase == .idle)
        #expect(model.notice == .failed(.auth(.invalidCredentials)))
        #expect(model.email == email)
        #expect(model.password == "wrong", "fields retain values after a credential error (01 §3)")
        #expect(model.failureCount == 1)
        #expect(model.rejectionCount == 1, "rejected credentials vibrate and shake once")
        #expect(model.fieldsEnabled)
    }

    @Test func aNetworkFailureIsNotARejection() async {
        let session = ScriptedSession()
        session.signInOutcome.set(.fail(.offline))
        let model = filled(session)
        await model.submit()
        #expect(model.notice == .failed(.offline))
        #expect(model.failureCount == 1)
        #expect(model.rejectionCount == 0, "a network failure is not the person's mistake")
    }

    @Test func unknownFailuresNeverCarryProviderText() async {
        struct ProviderError: Error, CustomStringConvertible {
            var description: String { "Firebase: Error (auth/wrong-password)." }
        }
        let session = ScriptedSession()
        let model = filled(session)
        // A thrown non-Waivera error maps to a generic case with client copy.
        session.signInOutcome.set(.fail(WaiveraError.from(ProviderError())))
        await model.submit()
        guard case .failed(let error) = model.notice else {
            Issue.record("expected a failure notice")
            return
        }
        #expect(!AuthStrings.failure(error).contains("Firebase"))
        #expect(AuthStrings.failure(error) == error.userMessage)
    }

    @Test func secondSubmitWhileSigningInIsIgnored() async {
        let session = ScriptedSession()
        session.signInOutcome.set(.hold)
        let model = filled(session)
        let first = Task { await model.submit() }
        #expect(await eventually { model.phase == .signingIn && session.calls.count == 1 })
        #expect(!model.fieldsEnabled)
        await model.submit()
        #expect(session.calls.count == 1)
        first.cancel()
        await first.value
    }

    /// 01 §8 check 1: the button shows a spinner labelled "Signing you in…" (Android's copy) while the
    /// backend bootstrap runs; the app then moves on and the form forgets the credentials.
    @Test func staysBusyThroughTheBootstrapThenForgetsCredentials() async {
        let session = ScriptedSession()
        let model = filled(session)
        let observing = Task { await model.observeSession() }
        defer { observing.cancel() }
        await model.submit()
        #expect(model.phase == .signingIn, "busy until the session reports the bootstrap, no flicker")
        #expect(model.isSigningIn)
        session.set(.bootstrapping)
        #expect(await eventually { model.isConnecting })
        #expect(model.isSigningIn)
        #expect(!model.fieldsEnabled)
        #expect(AuthStrings.connecting == "Signing you in…")
        session.set(.signedIn(DemoData.make().user))
        #expect(await eventually { !model.isConnecting })
        #expect(model.email.isEmpty)
        #expect(model.password.isEmpty)
        #expect(model.phase == .idle)
    }

    /// 01 §8 check 6: a 401 at bootstrap surfaces as an error on the sign-in screen.
    @Test func unauthorizedBootstrapIsSurfaced() async {
        let session = ScriptedSession()
        let model = filled(session)
        let observing = Task { await model.observeSession() }
        defer { observing.cancel() }
        await model.submit()
        session.set(.bootstrapping)
        session.set(.signedOut(.unauthorized))
        #expect(await eventually { model.notice == .failed(.unauthorized) })
        #expect(model.phase == .idle)
        #expect(model.password.isEmpty)
        #expect(model.failureCount == 1)
        #expect(model.fieldsEnabled)
    }

    @Test func signOutReasonShowsWhenTheScreenOpens() {
        let model = SignInModel(session: ScriptedSession(.signedOut(.unauthorized)))
        #expect(model.notice == .failed(.unauthorized))
    }

    @Test func plainSignOutShowsNothing() {
        let model = SignInModel(session: ScriptedSession(.signedOut(nil)))
        #expect(model.notice == nil)
        #expect(model.failureCount == 0)
    }

    @Test func gatesAfterSignInAlsoClearTheForm() {
        let model = filled(ScriptedSession())
        model.apply(.passwordChangeRequired(DemoData.make().user))
        #expect(model.email.isEmpty)
        #expect(model.password.isEmpty)
    }

    @Test func bootstrapFailureEndsTheBusyState() async {
        let session = ScriptedSession()
        let model = filled(session)
        await model.submit()
        model.apply(.bootstrapFailed(.offline))
        #expect(model.phase == .idle)
        #expect(!model.isSigningIn)
    }

    // MARK: Configuration

    /// 01 §8 check 11: missing configuration keeps the form disabled and never calls Firebase.
    @Test func missingConfigurationDisablesTheForm() async {
        let model = SignInModel(session: nil)
        #expect(!model.isConfigured)
        model.setEmail(email)
        model.setPassword("secret")
        #expect(!model.fieldsEnabled)
        #expect(!model.canSubmit)
        await model.submit()
        #expect(model.phase == .idle)
        #expect(model.notice == nil)
    }

    @Test func configurationMissingStateDisablesTheForm() async {
        let session = ScriptedSession(.configurationMissing)
        let model = SignInModel(session: session)
        #expect(!model.isConfigured)
        model.setEmail(email)
        model.setPassword("secret")
        await model.submit()
        #expect(session.calls.isEmpty)
    }

    // MARK: Against the shared fake

    @Test func demoPasswordSignsInThroughTheSharedFake() async {
        let fake = FakeDataEnvironment.make(.signedOut)
        let model = SignInModel(session: fake.session)
        let observing = Task { await model.observeSession() }
        defer { observing.cancel() }
        model.setEmail(email)
        model.setPassword(FakeSessionRepository.password)
        await model.submit()
        #expect(fake.session.currentState.isSignedIn)
        #expect(await eventually { model.password.isEmpty })
        #expect(model.notice == nil)
    }

    @Test func wrongPasswordFailsThroughTheSharedFake() async {
        let fake = FakeDataEnvironment.make(.signedOut)
        let model = SignInModel(session: fake.session)
        model.setEmail(email)
        model.setPassword("nope")
        await model.submit()
        #expect(model.notice == .failed(.auth(.invalidCredentials)))
        #expect(fake.session.calls.count("signIn") == 1)
    }

    // MARK: Password reset

    @Test func resetIsHiddenOnlyWithoutConfiguration() {
        #expect(!SignInModel(session: nil).canResetPassword)
        #expect(SignInModel(session: ScriptedSession()).canResetPassword)
        #expect(SignInModel(session: FakeDataEnvironment.make(.signedOut).session).canResetPassword)
    }

    @Test func resetNeedsAValidEmail() async {
        let sender = ScriptedSession()
        let model = SignInModel(session: sender)
        model.setEmail("alex")
        await model.sendPasswordReset()
        #expect(model.emailIssue == .emailInvalid)
        #expect(sender.calls.isEmpty)
    }

    @Test func resetSendsTheTrimmedEmail() async {
        let sender = ScriptedSession()
        let model = SignInModel(session: sender)
        model.setEmail(" \(email) ")
        await model.sendPasswordReset()
        #expect(sender.calls == ["reset:\(email)"])
        #expect(model.notice == .resetSent(email: email))
        #expect(model.successCount == 1)
    }

    @Test func unknownAccountReadsAsSent() async {
        let sender = ScriptedSession()
        sender.resetOutcome.set(.fail(.auth(.invalidCredentials)))
        let model = SignInModel(session: sender)
        model.setEmail(email)
        await model.sendPasswordReset()
        #expect(model.notice == .resetSent(email: email), "never reveal whether an account exists")
    }

    @Test func offlineResetShowsTheError() async {
        let sender = ScriptedSession()
        sender.resetOutcome.set(.fail(.offline))
        let model = SignInModel(session: sender)
        model.setEmail(email)
        await model.sendPasswordReset()
        #expect(model.notice == .failed(.offline))
        #expect(model.failureCount == 1)
        #expect(model.phase == .idle)
    }

    // MARK: Legal links

    @Test func anUnopenableLinkSaysSoWithoutTouchingTheForm() {
        let model = filled(ScriptedSession())
        model.linkUnavailable()
        #expect(model.notice == .linkUnavailable)
        #expect(model.email == email)
        #expect(model.password == "correct horse")
        #expect(model.rejectionCount == 0, "a link that will not open is not a rejection")
        #expect(model.failureCount == 0)
        model.dismissNotice()
        #expect(model.notice == nil)
    }

    @Test func emptyFieldsStillAnswerATap() async {
        // The button is enabled with empty fields (as on Android): a tap explains what is missing.
        let session = ScriptedSession()
        let model = SignInModel(session: session)
        #expect(model.fieldsEnabled)
        await model.submit()
        #expect(model.emailIssue == .emailRequired)
        #expect(model.passwordIssue == .passwordRequired)
        #expect(model.rejectionCount == 0, "a field error never vibrates or shakes")
    }

    // MARK: Privacy

    @Test func neverPrintsCredentials() {
        let model = filled(ScriptedSession(), password: "hunter2-secret")
        var dumped = ""
        dump(model, to: &dumped)
        for text in [String(describing: model), String(reflecting: model), dumped] {
            #expect(!text.contains("hunter2-secret"))
            #expect(!text.contains(email))
        }
    }
}
