import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ProfileFeature

struct PeopleFilterTests {
    private let viewer = CurrentUser(id: "usr_me", firebaseUid: "fb_me")

    @Test func dropsBlankNamesMissingIdsAndDuplicates() {
        let people = [
            DirectoryPerson(id: "a", name: "Alex Rivera"),
            DirectoryPerson(id: "b", name: "   "),
            DirectoryPerson(id: "", name: "No Id"),
            DirectoryPerson(id: "a", name: "Alex Again"),
        ]
        #expect(PeopleFilter.apply(people, me: nil, query: "").map(\.id) == ["a"])
    }

    @Test func excludesTheSignedInPersonByBackendIdOrFirebaseUid() {
        let people = [
            DirectoryPerson(id: "usr_me", name: "Me"),
            DirectoryPerson(id: "fb_me", name: "Me via Firebase"),
            DirectoryPerson(id: "p", name: "Priya Raman"),
        ]
        #expect(PeopleFilter.apply(people, me: viewer, query: "").map(\.id) == ["p"])
    }

    @Test func searchIsCaseInsensitiveSubstring() {
        let people = [DirectoryPerson(id: "p", name: "Priya Raman"), DirectoryPerson(id: "j", name: "Jordan Lee")]
        #expect(PeopleFilter.apply(people, me: viewer, query: "RAM").map(\.id) == ["p"])
        #expect(PeopleFilter.apply(people, me: viewer, query: "  lee ").map(\.id) == ["j"])
        #expect(PeopleFilter.apply(people, me: viewer, query: "zz").isEmpty)
    }
}

@MainActor
struct PeopleModelTests {
    @Test func listsCoworkersWithoutTheSignedInPerson() async {
        let fake = await launchedFake()
        let model = PeopleModel(environment: fake.environment)
        #expect(model.phase == .loading)
        await whileRunning(model.run) {
            await eventually { model.phase == .content }
            #expect(!model.rows.contains { $0.id == DemoData.viewerId })
            #expect(model.totalCount == model.rows.count)
            #expect(model.rows.count == fake.data.directory.count - 1)
        }
    }

    @Test func searchWithoutMatchesSaysSoAndKeepsTheTotal() async {
        let fake = await launchedFake()
        let model = PeopleModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .content }
            model.query = "zzz"
            #expect(model.phase == .noMatches)
            #expect(model.rows.isEmpty)
            #expect(model.totalCount > 0)
            model.query = "pri"
            #expect(model.phase == .content)
            #expect(model.rows.map(\.name) == ["Priya Raman"])
        }
    }

    @Test func emptyDirectoryShowsTheEmptyState() async {
        let fake = await launchedFake(.empty)
        let model = PeopleModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .empty }
        }
    }

    @Test func failureShowsTheErrorAndTheHeaderRefreshRetries() async {
        let fake = await launchedFake(.failing)
        let model = PeopleModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .failed(.server(statusCode: 503)) }
            fake.people.resource.setControls(FakeControls())
            await model.refresh()
            await eventually { model.phase == .content }
        }
    }

    @Test func aFailedRefreshKeepsTheListAndReportsInline() async {
        let fake = await launchedFake()
        let model = PeopleModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .content && !model.isRefreshing }
            fake.people.resource.setControls(FakeControls(failure: .offline))
            await model.refresh()
            await eventually { model.refreshError == .offline }
            #expect(model.phase == .content)
        }
    }

    @Test func aReconnectRefetchesTheDirectory() async {
        let fake = await launchedFake()
        let model = PeopleModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .content && !model.isRefreshing }
            let before = fake.people.resource.refreshCount
            fake.realtime.drop()
            fake.realtime.connect()
            await eventually { fake.people.resource.refreshCount > before }
        }
    }

    @Test func todaysMilestonesMarkTheRow() async {
        let fake = await launchedFake()
        let today = DemoData.today
        let milestone = Milestone(
            kind: .workAnniversary,
            userId: "usr_priya_raman",
            displayName: "Priya Raman",
            month: today.month,
            day: today.day,
            startYear: today.year - 5
        )
        fake.calendar.milestoneResource.setValue(MilestoneIndex([milestone]))
        await fake.calendar.refreshMilestones()
        let model = PeopleModel(environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.rows.contains { $0.celebration != nil } }
            let row = model.rows.first { $0.id == "usr_priya_raman" }
            #expect(row?.celebration?.anniversaryYears == 5)
        }
    }
}

@MainActor
struct PersonModelTests {
    @Test func showsTheDirectoryNameThenTheDetails() async {
        let fake = await launchedFake()
        await fake.people.refresh()
        let model = PersonModel(userID: "usr_priya_raman", environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.person != nil }
            #expect(model.displayName?.isEmpty == false)
            #expect(model.canMessage)
        }
    }

    @Test func failureShowsTheErrorAndLoadRetries() async {
        let fake = await launchedFake()
        let model = PersonModel(userID: "usr_nobody", environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.phase == .failed(.notFound) }
            await model.load()
            #expect(model.phase == .failed(.notFound))
        }
    }

    @Test func messageOpensTheExistingOrNewDirectConversation() async throws {
        let fake = await launchedFake()
        let model = PersonModel(userID: "usr_priya_raman", environment: fake.environment)
        await whileRunning(model.run) {
            await eventually { model.viewer != nil }
            let first = await model.message()
            #expect(first != nil)
            let again = await model.message()
            #expect(again == first)
            #expect(!model.isOpeningChat)
            // Someone with no conversation yet: the endpoint creates one.
            let newcomer = PersonModel(userID: "usr_sam_ortiz", environment: fake.environment)
            let created = await newcomer.message()
            #expect(created != nil)
            #expect(created != first)
        }
    }

    @Test func aFailedMessageStaysOnTheProfileWithAnError() async {
        let fake = await launchedFake()
        let model = PersonModel(
            userID: "usr_priya_raman",
            people: fake.people,
            conversations: FailingConversations(.offline),
            session: fake.session,
            calendar: fake.calendar,
            realtime: fake.realtimeStatus
        )
        let id = await model.message()
        #expect(id == nil)
        #expect(model.messageError == .offline)
        model.dismissMessageError()
        #expect(model.messageError == nil)
    }

    @Test func thereIsNoChatWithYourself() async {
        let fake = await launchedFake()
        let model = PersonModel(userID: DemoData.viewerId, environment: fake.environment)
        #expect(!model.canMessage)
        #expect(await model.message() == nil)
    }
}
