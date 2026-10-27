import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ProfileFeature

@MainActor
struct ProfileModelTests {
    @Test func loadsTheOwnProfileAfterTheLoadingState() async {
        let fake = await launchedFake()
        let clock = fake.clock as? ManualClock
        fake.profile.resource.setControls(FakeControls(latency: .seconds(1)))
        let model = ProfileModel(environment: fake.environment)
        #expect(model.phase == .loading)
        await whileRunning(model.run) {
            await eventually { (clock?.pendingSleepers ?? 0) > 0 }
            #expect(model.phase == .loading)
            #expect(model.isRefreshing)
            clock?.advance(by: 1)
            await eventually { model.phase == .loaded }
            #expect(!model.isRefreshing)
            #expect(model.content?.profile != nil)
            #expect(model.displayName != nil)
        }
    }

    @Test func aSectionRetryReloadsOnlyThatSection() async {
        let fake = await launchedFake()
        let model = ProfileModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .loaded }
            fake.profile.resource.mutate { $0.sections.timeOff = .failed(.offline) }
            await eventually { model.content?.sections.timeOff == .failed(.offline) }
            #expect(model.phase == .loaded, "a section failure never fails the screen")
            let before = fake.profile.resource.refreshCount
            await model.retry(section: .timeOff)
            #expect(fake.profile.calls.all == ["refreshSection:timeOff"])
            #expect(fake.profile.resource.refreshCount == before)
            await eventually { model.content?.sections.timeOff == .loaded }
        }
    }

    @Test func missingBackendIdShowsOneUnavailableState() async {
        let fake = FakeDataEnvironment.make(.signedOut, clock: ManualClock())
        let model = ProfileModel(environment: fake.environment)
        #expect(model.phase == .unavailable)
        await whileRunning(model.run) {
            try? await Task.sleep(for: .milliseconds(50))
            #expect(model.phase == .unavailable)
            #expect(fake.profile.resource.refreshCount == 0)
        }
    }

    @Test func failureShowsTheErrorAndRetryReissuesTheRequests() async {
        let fake = await launchedFake(.failing)
        let model = ProfileModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .failed(.server(statusCode: 503)) }
            let before = fake.profile.resource.refreshCount
            fake.profile.resource.setControls(FakeControls())
            await model.refresh()
            #expect(fake.profile.resource.refreshCount == before + 1)
            await eventually { model.phase == .loaded }
        }
    }

    @Test func aFailedRefreshKeepsTheProfileAndReportsInline() async {
        let fake = await launchedFake()
        let model = ProfileModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .loaded }
            fake.profile.resource.setControls(FakeControls(failure: .offline))
            await model.refresh()
            await eventually { model.refreshError == .offline }
            #expect(model.phase == .loaded)
            #expect(model.content?.profile != nil)
        }
    }

    @Test func refreshShowsBusyUntilTheRequestSettlesAndIgnoresDoubleTaps() async {
        let fake = await launchedFake()
        let clock = fake.clock as? ManualClock
        let model = ProfileModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .loaded && !model.isRefreshing }
            let before = fake.profile.resource.refreshCount
            fake.profile.resource.setControls(FakeControls(latency: .seconds(2)))
            let first = Task { await model.refresh() }
            await eventually { (clock?.pendingSleepers ?? 0) > 0 }
            #expect(model.isRefreshing)
            await model.refresh()
            #expect(fake.profile.resource.refreshCount == before + 1)
            clock?.advance(by: 2)
            await first.value
            #expect(!model.isRefreshing)
        }
    }

    @Test func aReconnectRefreshesTheProfile() async {
        let fake = await launchedFake()
        let model = ProfileModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .loaded && !model.isRefreshing }
            let before = fake.profile.resource.refreshCount
            fake.realtime.drop()
            fake.realtime.connect()
            await eventually { fake.profile.resource.refreshCount > before }
        }
    }

    @Test func aMissingOrganizationMatchIsUnavailable() async {
        let fake = await launchedFake()
        var profile = fake.data.profile
        profile.organization = nil
        fake.profile.resource.setValue(profile)
        let model = ProfileModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .loaded && !model.isRefreshing }
            #expect(model.content?.organization == nil)
        }
    }

    @Test func todaysBirthdayShowsTheCelebration() async throws {
        let fake = await launchedFake()
        let today = DemoData.today
        let milestone = Milestone(
            kind: .birthday,
            userId: DemoData.viewerId,
            displayName: "Alex Rivera",
            month: today.month,
            day: today.day
        )
        fake.calendar.milestoneResource.setValue(MilestoneIndex([milestone]))
        await fake.calendar.refreshMilestones()
        let model = ProfileModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.celebration != nil }
            #expect(model.celebration?.isBirthday == true)
        }
    }
}
