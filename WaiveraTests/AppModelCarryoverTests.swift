import Foundation
import Testing
import WaiveraData
import WaiveraNotifications
import WaiveraRouting
import WaiveraTestSupport

@testable import Waivera

/// The shell side of the feature requests and the Android review carry-over: held gates, a
/// cold-launch notification action, nothing shown or kept for a signed-out device.
@MainActor
struct AppModelCarryoverTests {
    @Test func aReRunLoginKeepsTheGateItStartedFrom() {
        let user = CurrentUser(id: "usr_me", firebaseUid: "fb_me", displayName: "Me")
        #expect(AppModel.gateHeld(whileRebootstrappingFrom: .bootstrapFailed(.offline)) == .bootstrapFailed)
        #expect(AppModel.gateHeld(whileRebootstrappingFrom: .passwordChangeRequired(user)) == .passwordChange)
        #expect(AppModel.gateHeld(whileRebootstrappingFrom: .onboardingRequired(user)) == .onboardingRequired)
        #expect(AppModel.gateHeld(whileRebootstrappingFrom: .signedOut(nil)) == nil)
        #expect(
            AppModel.sessionGate(for: .bootstrapping, hasShownSignIn: true, heldGate: .passwordChange)
                == .passwordChange
        )
        #expect(AppModel.sessionGate(for: .bootstrapping, hasShownSignIn: true) == .signIn)
        #expect(AppModel.sessionGate(for: .bootstrapping, hasShownSignIn: false) == .loading)
    }

    @Test func retryFromTheFailedGateNeverFlashesSignIn() async {
        let harness = AppModelHarness(scenario: .signedOut)
        harness.fakes.session.bootstrapFailure.update { $0 = .offline }
        harness.model.start()
        await harness.settle()
        try? await harness.fakes.session.signIn(email: "alex@example.com", password: FakeSessionRepository.password)
        #expect(await harness.until { harness.model.gate == .bootstrapFailed })
        harness.fakes.session.bootstrapFailure.update { $0 = nil }
        harness.fakes.session.holdsBootstrap.update { $0 = true }
        harness.model.retryBootstrap()
        #expect(await harness.until { harness.model.session == .bootstrapping })
        #expect(harness.model.gate == .bootstrapFailed)
        harness.fakes.session.releaseBootstrap()
        #expect(await harness.until { harness.model.gate == nil })
    }

    @Test func aReplyThatColdLaunchedTheAppWaitsForTheSession() async {
        let harness = AppModelHarness()
        let event = NotificationResponseEvent(
            key: "cold",
            actionIdentifier: NotificationActionID.reply,
            payload: .chat(ChatPush(conversationID: 7, messageID: 9312)),
            userText: "on my way"
        )
        let reply = Task { await harness.model.handle(event) }
        await harness.settle()
        harness.model.start()
        await reply.value
        #expect(harness.fakes.chat.calls.count("send:7") == 1)
    }

    @Test func nothingIsPresentedWhileSignedOut() async {
        let harness = AppModelHarness(scenario: .signedOut)
        harness.model.start()
        await harness.settle()
        let decision = harness.model.presentationDecision(for: .chat(ChatPush(conversationID: 7, messageID: 1)))
        #expect(decision == .suppressed)
    }

    @Test func signOutDeletesThePushToken() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        #expect(harness.tokens.invalidations.get() == 0)
        harness.model.signOut()
        #expect(await harness.until { harness.tokens.invalidations.get() == 1 })
    }
}

struct LaunchOptionsTests {
    @Test func aStateVariantPicksItsScenario() {
        let options = LaunchOptions.parse(["-WaiveraFakeServer", "-WaiveraRoute", "today-empty"])
        #expect(options.fakeScenario == .empty)
        #expect(options.route?.name == "today-empty")
        let explicit = LaunchOptions.parse([
            "-WaiveraFakeServer", "-WaiveraFakeScenario", "failing", "-WaiveraRoute", "today-empty",
        ])
        #expect(explicit.fakeScenario == .failing)
        let live = LaunchOptions.parse(["-WaiveraRoute", "today-empty"])
        #expect(live.fakeScenario == nil, "a route never turns the fake server on by itself")
    }
}
