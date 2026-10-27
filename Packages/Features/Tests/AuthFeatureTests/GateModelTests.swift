import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import AuthFeature

@MainActor
@Suite("Gate models")
struct GateModelTests {
    private var user: CurrentUser { DemoData.make().user }

    // MARK: Bootstrap failed

    @Test func showsTheFailureFromTheSession() {
        let model = BootstrapFailedModel(session: ScriptedSession(.bootstrapFailed(.offline)), onRetry: {})
        #expect(model.error == .offline)
        #expect(model.isOffline)
        let server = BootstrapFailedModel(
            session: ScriptedSession(.bootstrapFailed(.server(statusCode: 503))),
            onRetry: {}
        )
        #expect(!server.isOffline)
    }

    @Test func retryRunsOnceUntilTheSessionAnswers() {
        var retries = 0
        let model = BootstrapFailedModel(
            session: ScriptedSession(.bootstrapFailed(.offline)),
            onRetry: { retries += 1 }
        )
        model.retry()
        model.retry()
        #expect(retries == 1)
        #expect(model.isRetrying)
        model.apply(.bootstrapping)
        #expect(model.isRetrying)
        model.apply(.bootstrapFailed(.server(statusCode: 500)))
        #expect(!model.isRetrying)
        #expect(model.error == .server(statusCode: 500))
        #expect(model.failureCount == 1, "a failed retry plays the error haptic")
        model.retry()
        #expect(retries == 2)
    }

    @Test func retryEndsWhenTheSessionMovesOn() async {
        let session = ScriptedSession(.bootstrapFailed(.offline))
        let model = BootstrapFailedModel(session: session, onRetry: { session.set(.bootstrapping) })
        let observing = Task { await model.observeSession() }
        defer { observing.cancel() }
        model.retry()
        session.set(.signedIn(user))
        #expect(await eventually { !model.isRetrying })
        #expect(model.failureCount == 0)
    }

    // MARK: Onboarding

    @Test func checkAgainWhileStillPending() async {
        let session = ScriptedSession(.onboardingRequired(user))
        session.retryResult.set(.onboardingRequired(user))
        let model = OnboardingModel(session: session)
        await model.checkAgain()
        #expect(model.status == .stillPending)
        #expect(model.failureCount == 1)
        #expect(session.calls == ["retryBootstrap"])
    }

    @Test func checkAgainThatFails() async {
        let session = ScriptedSession(.onboardingRequired(user))
        session.retryResult.set(.bootstrapFailed(.offline))
        let model = OnboardingModel(session: session)
        await model.checkAgain()
        #expect(model.status == .failed(.offline))
    }

    @Test func checkAgainThatSucceedsLeavesTheGateToTheApp() async {
        let session = ScriptedSession(.onboardingRequired(user))
        session.retryResult.set(.signedIn(user))
        let model = OnboardingModel(session: session)
        await model.checkAgain()
        #expect(model.status == .waiting)
        #expect(model.failureCount == 0)
    }

    @Test func liveStyleAnswerArrivesThroughTheStream() async {
        let session = ScriptedSession(.onboardingRequired(user))
        let model = OnboardingModel(session: session)
        let observing = Task { await model.observeSession() }
        defer { observing.cancel() }
        await model.checkAgain()
        #expect(model.isChecking, "still waiting for the backend login")
        #expect(!model.canCheck)
        session.set(.onboardingRequired(user))
        #expect(await eventually { model.status == .stillPending })
        #expect(model.failureCount == 1)
    }

    @Test func withoutASessionThereIsNothingToCheck() async {
        let model = OnboardingModel(session: nil)
        #expect(!model.canCheck)
        await model.checkAgain()
        #expect(model.status == .waiting)
    }

    // MARK: Configuration

    @Test func reportsMissingSettingNames() {
        let report = ConfigurationReport.make(info: ["WaiveraAPIBaseURL": "$(WAIVERA_API_BASE_URL)"])
        #expect(report.missingKeys == ["WaiveraAPIBaseURL", "WaiveraFirebaseAPIKey"])
    }

    @Test func completeConfigurationReportsNothing() {
        let report = ConfigurationReport.make(info: [
            "WaiveraAPIBaseURL": "https://api.example.org",
            "WaiveraFirebaseAPIKey": "key",
        ])
        #expect(report.missingKeys.isEmpty)
        let details = AuthStrings.configurationDetails(["WaiveraAPIBaseURL"])
        #expect(details.contains("WaiveraAPIBaseURL"))
    }
}
