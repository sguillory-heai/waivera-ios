import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraNotifications
import WaiveraTestSupport

@testable import SettingsFeature

@MainActor
private func eventually(_ timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Condition not met in time")
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func launchedFake(_ scenario: FakeDataEnvironment.Scenario = .demo) async -> FakeDataEnvironment {
    let fake = FakeDataEnvironment.make(scenario, clock: ManualClock())
    await fake.environment.launch()
    await eventually { fake.session.currentState.isSignedIn }
    return fake
}

struct NotificationSwitchesTests {
    @Test func meaningsMapOntoTheServerFlags() {
        var preferences = NotificationPreferences()
        NotificationSwitches.set(.groupActivity, to: false, in: &preferences)
        #expect(!preferences.reactions)
        #expect(preferences.chatMessages, "direct messages still need chat pushes")
        NotificationSwitches.set(.messages, to: false, in: &preferences)
        #expect(!preferences.mentions && !preferences.activeCalls)
        #expect(!preferences.chatMessages)
        NotificationSwitches.set(.groupActivity, to: true, in: &preferences)
        #expect(preferences.chatMessages)
        #expect(NotificationSwitches.isOn(.groupActivity, in: preferences))
        #expect(!NotificationSwitches.isOn(.messages, in: preferences))
    }

    @Test func meaningsWithoutAFlagAreNotOfferedAndChangeNothing() {
        #expect(NotificationSwitches.offered == [.messages, .groupActivity])
        var preferences = NotificationPreferences()
        NotificationSwitches.set(.digest, to: false, in: &preferences)
        #expect(preferences == NotificationPreferences())
    }
}

@MainActor
struct NotificationSettingsModelTests {
    @Test func pushOffDisablesTheRestWithoutChangingThem() async {
        var stored = AppSettings()
        stored.notifications.reactions = false
        stored.notifications.previewContent = false
        let settings = FakeSettingsRepository(stored)
        let model = NotificationSettingsModel(settings: settings)
        await model.setPushEnabled(false)
        #expect(!model.categoriesEnabled)
        #expect(!settings.currentSettings.notifications.pushEnabled)
        // Switches are ignored while push is off; stored values stay as they were.
        await model.set(.groupActivity, isOn: true)
        await model.setPreviewContent(true)
        #expect(!settings.currentSettings.notifications.reactions)
        #expect(!settings.currentSettings.notifications.previewContent)
        await model.setPushEnabled(true)
        var expected = stored.notifications
        expected.pushEnabled = true
        #expect(settings.currentSettings.notifications == expected)
        #expect(!model.isOn(.groupActivity))
    }

    @Test func eachSwitchWritesOnceAndRepeatsAreIgnored() async {
        let settings = FakeSettingsRepository()
        let model = NotificationSettingsModel(settings: settings)
        await model.set(.messages, isOn: false)
        await model.setInAppBanners(false)
        await model.setInAppSound(false)
        #expect(!settings.currentSettings.notifications.mentions)
        #expect(!settings.currentSettings.notifications.inAppBanners)
        #expect(!settings.currentSettings.notifications.sound)
        await model.set(.messages, isOn: false)
        #expect(!model.isOn(.messages))
    }

    @Test func followsTheStoredSettings() async {
        let settings = FakeSettingsRepository()
        let model = NotificationSettingsModel(settings: settings)
        let task = Task { await model.run() }
        defer { task.cancel() }
        await eventually { model.isLoaded }
        await settings.update { $0.notifications.previewContent = false }
        await eventually { !model.preferences.previewContent }
    }
}

@MainActor
struct AppearanceModelTests {
    @Test func selectionAndHapticsPersist() async {
        let settings = FakeSettingsRepository()
        let model = AppearanceModel(settings: settings)
        #expect(model.appearance == .system)
        await model.select(.dark)
        await model.setHapticsEnabled(false)
        #expect(settings.currentSettings.appearance == .dark)
        #expect(!settings.currentSettings.hapticsEnabled)
        let reopened = AppearanceModel(settings: settings)
        #expect(reopened.appearance == .dark)
        #expect(!reopened.hapticsEnabled)
    }
}

@MainActor
struct AccountModelTests {
    @Test func signOutConfirmsOnceAndUnregistersPush() async {
        let fake = await launchedFake()
        let model = AccountModel(environment: fake.environment)
        let task = Task { await model.run() }
        defer { task.cancel() }
        #expect(model.account?.email != nil)
        model.requestSignOut()
        #expect(model.isConfirmingSignOut)
        #expect(model.confirmSignOut())
        await fake.session.signOut()
        #expect(!model.confirmSignOut(), "a second sign-out is a no-op")
        #expect(fake.push.unregisterCount.get() == 1)
        #expect(fake.session.currentState == .signedOut(nil))
        await eventually { model.account == nil }
        model.requestSignOut()
        #expect(!model.isConfirmingSignOut)
    }

    @Test func summaryUsesTheNameAndOrganization() {
        let user = CurrentUser(
            id: "u1",
            firebaseUid: "f1",
            email: "priya@example.com",
            firstName: "Priya",
            lastName: "Raman",
            organization: Organization(id: 4, name: "Sprout Care")
        )
        let summary = AccountSummary(user: user)
        #expect(summary.name == "Priya Raman")
        #expect(summary.email == "priya@example.com")
        #expect(summary.organization == "Sprout Care")
        let emailOnly = AccountSummary(user: CurrentUser(id: "u2", firebaseUid: "f2", email: "sam@example.com"))
        #expect(emailOnly.name == nil)
    }
}

@MainActor
struct ChangePasswordModelTests {
    @Test func validationShowsEveryProblemAtOnce() async {
        let fake = await launchedFake()
        let model = ChangePasswordModel(session: fake.session)
        model.new = "short"
        model.confirmation = "different"
        #expect(!model.validate())
        #expect(model.currentError == .currentRequired)
        #expect(model.newError == .tooShort(minimum: 8))
        #expect(model.confirmationError == .mismatch)
        model.current = "same-password"
        model.new = "same-password"
        model.confirmation = "same-password"
        #expect(!model.validate())
        #expect(model.newError == .sameAsCurrent)
        #expect(fake.session.calls.count("changePassword") == 0)
    }

    @Test func aWrongCurrentPasswordIsAFieldError() async {
        let fake = await launchedFake()
        let model = ChangePasswordModel(session: fake.session)
        model.current = "not-the-password"
        model.new = "a-new-password"
        model.confirmation = "a-new-password"
        #expect(await model.submit() == false)
        #expect(model.currentError == .currentWrong)
        #expect(model.failure == nil)
        #expect(!model.didSucceed)
    }

    @Test func successClearsTheFieldsAndIgnoresAnotherSubmit() async {
        let fake = await launchedFake()
        let model = ChangePasswordModel(session: fake.session)
        model.current = FakeSessionRepository.password
        model.new = "a-new-password"
        model.confirmation = "a-new-password"
        #expect(await model.submit())
        #expect(model.didSucceed)
        #expect(model.current.isEmpty && model.new.isEmpty && model.confirmation.isEmpty)
        #expect(await model.submit() == false)
        #expect(fake.session.calls.count("changePassword") == 1)
    }
}

@MainActor
struct SwitchBindingTests {
    @Test func bindingChangesApplyInOrder() async {
        let settings = FakeSettingsRepository()
        let notifications = NotificationSettingsModel(settings: settings)
        notifications.apply(.meaning(.groupActivity, false))
        notifications.apply(.push(false))
        notifications.apply(.previews(false))
        await notifications.waitForWrites()
        #expect(!settings.currentSettings.notifications.reactions)
        #expect(!settings.currentSettings.notifications.pushEnabled)
        #expect(settings.currentSettings.notifications.previewContent, "ignored while push is off")
        let appearance = AppearanceModel(settings: settings)
        appearance.choose(.light)
        appearance.toggleHaptics(false)
        await appearance.waitForWrites()
        #expect(settings.currentSettings.appearance == .light)
        #expect(!settings.currentSettings.hapticsEnabled)
    }
}
