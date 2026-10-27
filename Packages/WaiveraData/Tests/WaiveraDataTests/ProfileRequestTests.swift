import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures

@testable import WaiveraData

@Suite("Profile requests")
struct ProfileRequestTests {
    private func routes(_ transport: RoutingTransport) async {
        await transport.set("GET api/employee/getProfile/usr_alex_rivera", .fixture("rest-employee-get-profile"))
        await transport.set(
            "GET api/TimeOff/get-timeOffs-for-user-profile/usr_alex_rivera",
            .fixture("rest-timeoff-get-for-user-profile")
        )
        await transport.set("GET api/employee/get-employee-files", .fixture("rest-employee-get-employee-files"))
        await transport.set("GET api/Authentication/OrganizationDetails", .fixture("rest-auth-organization-details"))
    }

    private func make(user: CurrentUser) async -> (LiveProfileRepository, RoutingTransport) {
        let transport = RoutingTransport()
        await routes(transport)
        let repository = LiveProfileRepository(
            api: makeAPI(transport),
            context: SessionContext(user: user),
            store: InMemoryLocalStore(),
            clock: TestClock()
        )
        return (repository, transport)
    }

    @Test("Profile request 1: an organization id miss is unavailable, not the session's copy")
    func organizationMissIsNil() async {
        var user = alex
        user.organization = Organization(id: 404, name: "Session copy")
        let (repository, _) = await make(user: user)
        await repository.refresh()
        let value = await latest(repository.profile())?.value
        #expect(value?.profile != nil)
        #expect(value?.organization == nil)
    }

    @Test("Profile request 2: a card fails on its own and its Retry reloads only that card")
    func sectionPhases() async {
        let (repository, transport) = await make(user: alex)
        await transport.set("GET api/employee/get-employee-files", .status(503))
        await repository.refresh()
        var value = await latest(repository.profile())?.value
        #expect(value?.sections.timeOff == .loaded)
        #expect(value?.sections.files == .failed(.server(statusCode: 503)))
        await transport.set("GET api/employee/get-employee-files", .fixture("rest-employee-get-employee-files"))
        await repository.refresh(section: .files)
        value = await latest(repository.profile())?.value
        #expect(value?.sections.files == .loaded)
        #expect(value?.files.count == 1)
        #expect(await transport.count("GET api/employee/getProfile/usr_alex_rivera") == 1)
    }

    @Test("Profile request 3: SCID, waiver families and agencies")
    func professionalFields() async throws {
        var user = alex
        user.scId = "SC-1042"
        let (repository, _) = await make(user: user)
        await repository.refresh()
        let profile = try #require(await latest(repository.profile())?.value?.profile)
        #expect(profile.scId == "SC-1042")
        #expect(profile.agencies == ["Northside Supports"])
        #expect(profile.waiverFamilies == ["CAC"])
    }

    @Test("SCID comes from the session's user details")
    func scIdFromUserDetails() throws {
        let details = try decodeFixture(ApiResponse<UserWithRoleDto>.self, "rest-auth-get-user-details").data
        let login = try WaiveraJSON.decoder().decode(
            UserLoginResponseDto.self,
            from: Data(#"{"requiresPasswordChange":false,"userId":"usr_alex_rivera","requiresOnboarding":false}"#.utf8)
        )
        let user = ProfileMapper.currentUser(
            login: login,
            identity: FirebaseIdentity(uid: "fb", email: nil, displayName: nil),
            details: details,
            organization: nil
        )
        #expect(user.scId == "SC-4821")
    }
}
