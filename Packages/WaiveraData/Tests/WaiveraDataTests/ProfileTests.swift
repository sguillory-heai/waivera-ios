import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Profile and people")
struct ProfileTests {
    private var alexAtNorthside: CurrentUser {
        var user = alex
        user.organization = Organization(id: 12, name: "Northside Supports")
        return user
    }

    private func profileRoutes(_ transport: RoutingTransport) async {
        await transport.set("GET api/employee/getProfile/usr_alex_rivera", .fixture("rest-employee-get-profile"))
        await transport.set(
            "GET api/TimeOff/get-timeOffs-for-user-profile/usr_alex_rivera",
            .fixture("rest-timeoff-get-for-user-profile")
        )
        await transport.set("GET api/employee/get-employee-files", .fixture("rest-employee-get-employee-files"))
        await transport.set("GET api/Authentication/OrganizationDetails", .fixture("rest-auth-organization-details"))
    }

    @Test func profileMatchesTheOrganizationById() async {
        let transport = RoutingTransport()
        await profileRoutes(transport)
        let repository = LiveProfileRepository(
            api: makeAPI(transport),
            context: SessionContext(user: alexAtNorthside),
            store: InMemoryLocalStore(),
            clock: TestClock()
        )
        await repository.refresh()
        let value = await latest(repository.profile())?.value
        #expect(value?.profile != nil)
        #expect(value?.timeOff != nil)
        #expect(value?.files.count == 1)
        #expect(value?.organization?.address == "900 Example Ave, Springfield")
    }

    @Test func organizationIsNeverMatchedByName() throws {
        let session = Organization(id: 99, name: "Northside Supports")
        let list = try WaiveraJSON.decoder().decode(
            [OrganizationDto].self,
            from: Data(#"[{"id":12,"name":"Northside Supports","address":"elsewhere"}]"#.utf8)
        )
        #expect(LiveProfileRepository.organization(session, in: list)?.address == nil)
    }

    @Test func sectionsFailIndependently() async {
        let transport = RoutingTransport()
        await profileRoutes(transport)
        await transport.set("GET api/TimeOff/get-timeOffs-for-user-profile/usr_alex_rivera", .status(500))
        let repository = LiveProfileRepository(
            api: makeAPI(transport),
            context: SessionContext(user: alex),
            store: InMemoryLocalStore(),
            clock: TestClock()
        )
        await repository.refresh()
        let resource = await latest(repository.profile())
        #expect(resource?.phase == .loaded)
        #expect(resource?.value?.timeOff == nil)

        await transport.set("GET api/employee/getProfile/usr_alex_rivera", .status(404))
        await repository.refresh()
        #expect(await latest(repository.profile())?.error == .notFound)
    }

    @Test func directoryIsTheCallersOrganizationSortedWithoutParticipants() async {
        let transport = RoutingTransport()
        await transport.set("GET api/users", .fixture("rest-users-list"))
        let people = LivePeopleRepository(api: makeAPI(transport), store: InMemoryLocalStore(), clock: TestClock())
        await people.refresh()
        let names = await latest(people.directory())?.value?.map(\.name)
        #expect(names == ["Alex Rivera", "Jordan Lee", "Priya Raman"])
    }

    @Test func directoryDropsDuplicatesDeactivatedAndNamelessRows() async {
        let transport = RoutingTransport()
        let users = #"""
            [{"id":"usr_a","firstName":"Ann","lastName":"Bell"},{"id":"usr_a","displayName":"Ann Again"},
             {"id":"usr_gone","displayName":"Gone","deactivated":true},{"id":"usr_mail","email":"m@example.com"},
             {"id":" ","displayName":"Blank"},{"id":"usr_none"}]
            """#
        await transport.set("GET api/users", .json(users))
        let people = LivePeopleRepository(api: makeAPI(transport), store: InMemoryLocalStore(), clock: TestClock())
        await people.refresh()
        let directory = await latest(people.directory())?.value
        #expect(directory?.map(\.id) == ["usr_a", "usr_mail"])
        #expect(directory?.map(\.name) == ["Ann Bell", "m@example.com"])
    }

    @Test func anOldCrossOrganizationCacheIsDeletedNotShown() async {
        let store = InMemoryLocalStore()
        await store.save([DirectoryPerson(id: "usr_other_agency", name: "Other Agency")], for: .legacyDirectory)
        let people = LivePeopleRepository(api: makeAPI(RoutingTransport()), store: store, clock: TestClock())
        await people.begin()
        #expect(await latest(people.directory())?.value == nil)
        #expect(await store.data(for: .legacyDirectory) == nil)
    }

    @Test func directoryNeverReadsTheCrossOrganizationList() async {
        let transport = RoutingTransport()
        await transport.set("GET api/users", .fixture("rest-users-list"))
        let people = LivePeopleRepository(api: makeAPI(transport), store: InMemoryLocalStore(), clock: TestClock())
        await people.refresh()
        #expect(await transport.count("GET api/Authentication/get-username-list") == 0)
        #expect(await transport.count("GET api/users") == 1)
    }
}
