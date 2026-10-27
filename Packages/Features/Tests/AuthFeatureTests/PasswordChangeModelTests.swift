import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import AuthFeature

@MainActor
@Suite("Password change model")
struct PasswordChangeModelTests {
    private let newPassword = "a brand new phrase"

    private func filled(_ model: PasswordChangeModel, current: String = "old secret") -> PasswordChangeModel {
        model.set(.current, to: current)
        model.set(.new, to: newPassword)
        model.set(.confirmation, to: newPassword)
        return model
    }

    @Test func buttonNeedsAllThreeFields() {
        let model = PasswordChangeModel(mode: .required, session: ScriptedSession())
        #expect(!model.canSubmit)
        model.set(.current, to: "old")
        model.set(.new, to: "new")
        #expect(!model.canSubmit)
        model.set(.confirmation, to: "new")
        #expect(model.canSubmit)
    }

    @Test func invalidInputIsExplainedFocusedAndNotSent() async {
        let session = ScriptedSession()
        let model = PasswordChangeModel(mode: .required, session: session)
        model.set(.current, to: "old secret")
        model.set(.new, to: "short")
        model.set(.confirmation, to: "other")
        await model.submit()
        #expect(model.issues.new == .newPasswordTooShort(minimum: AuthValidation.minimumNewPasswordLength))
        #expect(model.issues.confirmation == .confirmationMismatch)
        #expect(model.focusRequest == .new)
        #expect(model.failureCount == 1)
        #expect(session.calls.isEmpty)
        #expect(!model.showsNewPasswordHint)
        model.focusHandled()
        #expect(model.focusRequest == nil)
    }

    @Test func sendsCurrentAndNewUntouched() async {
        let session = ScriptedSession()
        let model = filled(PasswordChangeModel(mode: .required, session: session), current: " old secret ")
        await model.submit()
        #expect(session.calls == ["changePassword: old secret :\(newPassword)"])
    }

    @Test func successClearsEverySecret() async {
        let session = ScriptedSession()
        let model = filled(PasswordChangeModel(mode: .voluntary, session: session))
        await model.submit()
        #expect(model.phase == .done)
        #expect(model.current.isEmpty)
        #expect(model.new.isEmpty)
        #expect(model.confirmation.isEmpty)
        #expect(model.successCount == 1)
        #expect(!model.fieldsEnabled)
        model.set(.current, to: "x")
        #expect(model.phase == .editing, "typing again starts a new change")
    }

    @Test func wrongCurrentPasswordPointsAtThatField() async {
        let session = ScriptedSession()
        session.changeOutcome.set(.fail(.auth(.invalidCredentials)))
        let model = filled(PasswordChangeModel(mode: .required, session: session))
        await model.submit()
        #expect(model.phase == .editing)
        #expect(model.current.isEmpty)
        #expect(model.new == newPassword)
        #expect(model.issues.current == .currentPasswordWrong)
        #expect(model.focusRequest == .current)
        #expect(model.error == nil)
    }

    @Test func weakPasswordPointsAtTheNewField() async {
        let session = ScriptedSession()
        session.changeOutcome.set(.fail(.auth(.weakPassword)))
        let model = filled(PasswordChangeModel(mode: .required, session: session))
        await model.submit()
        #expect(model.issues.new == .newPasswordWeak)
        #expect(model.focusRequest == .new)
    }

    @Test func offlineShowsAMappedErrorAndKeepsTheForm() async {
        let session = ScriptedSession()
        session.changeOutcome.set(.fail(.offline))
        let model = filled(PasswordChangeModel(mode: .required, session: session))
        await model.submit()
        #expect(model.error == .offline)
        #expect(model.new == newPassword)
        #expect(model.failureCount == 1)
        #expect(model.fieldsEnabled)
        model.dismissError()
        #expect(model.error == nil)
    }

    @Test func secondSubmitWhileSavingIsIgnored() async {
        let session = ScriptedSession()
        session.changeOutcome.set(.hold)
        let model = filled(PasswordChangeModel(mode: .required, session: session))
        let first = Task { await model.submit() }
        #expect(await eventually { model.isSaving && session.calls.count == 1 })
        #expect(!model.fieldsEnabled)
        await model.submit()
        #expect(session.calls.count == 1)
        first.cancel()
        await first.value
    }

    @Test func signOutWipesWhatWasTyped() async {
        let session = ScriptedSession(.passwordChangeRequired(DemoData.make().user))
        let model = filled(PasswordChangeModel(mode: .required, session: session))
        let observing = Task { await model.observeSession() }
        defer { observing.cancel() }
        await session.signOut()
        #expect(await eventually { model.current.isEmpty && model.new.isEmpty && model.confirmation.isEmpty })
    }

    @Test func withoutASessionNothingCanBeSubmitted() async {
        let model = filled(PasswordChangeModel(mode: .required, session: nil))
        #expect(!model.fieldsEnabled)
        await model.submit()
        #expect(model.phase == .editing)
    }

    /// 01 §8 check 2 (the gate part the feature owns): once the change succeeds the session
    /// leaves `passwordChangeRequired`, so the app's gate opens.
    @Test func requiredChangeClearsTheGateThroughTheSharedFake() async {
        let fake = FakeDataEnvironment.make(.passwordChange)
        await fake.session.start()
        guard case .passwordChangeRequired = fake.session.currentState else {
            Issue.record("expected the password change gate")
            return
        }
        let model = filled(
            PasswordChangeModel(mode: .required, session: fake.session),
            current: FakeSessionRepository.password
        )
        await model.submit()
        #expect(model.phase == .done)
        #expect(fake.session.currentState.isSignedIn)
    }

    @Test func wrongCurrentThroughTheSharedFake() async {
        let fake = FakeDataEnvironment.make(.passwordChange)
        await fake.session.start()
        let model = filled(PasswordChangeModel(mode: .required, session: fake.session), current: "nope")
        await model.submit()
        #expect(model.issues.current == .currentPasswordWrong)
        guard case .passwordChangeRequired = fake.session.currentState else {
            Issue.record("the gate must stay closed")
            return
        }
    }

    @Test func neverPrintsPasswords() {
        let model = filled(PasswordChangeModel(mode: .required, session: ScriptedSession()), current: "hunter2-old")
        var dumped = ""
        dump(model, to: &dumped)
        for text in [String(describing: model), String(reflecting: model), dumped] {
            #expect(!text.contains("hunter2-old"))
            #expect(!text.contains(newPassword))
        }
    }
}
