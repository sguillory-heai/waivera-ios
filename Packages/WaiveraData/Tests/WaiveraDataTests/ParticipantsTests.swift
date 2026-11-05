import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraData

@Suite("Participant profile")
struct ParticipantsTests {
    private let me = CurrentUser(id: "u-alex", firebaseUid: "fb-alex")

    private let info = #"""
        {"id":501,"firstName":" Jordan ","lastName":"Lee","dateOfBirth":"1988-06-02T00:00:00",
         "intakeType":"Transition","region":{"regionId":4,"regionName":"Region 4"},"deactivated":false,
         "linkageDate":"2025-02-10T00:00:00","cpocDate":"2026-04-01T00:00:00","cpocEndDate":"2027-03-31T00:00:00",
         "email":" ","mobileNumber":"(555) 010-2231","waiver":{"id":2,"waiverName":"","code":"CC"},
         "isCompliant":true,"ssnLastFour":"1234"}
        """#

    private func task(_ id: Int, due: String?, status: String = "In Progress") -> String {
        let end = due.map { #","endDate":"\#($0)T00:00:00""# } ?? ""
        return #"{"id":\#(id),"friendlyId":\#(id),"title":"T\#(id)","taskStatus":{"name":"\#(status)"}\#(end)}"#
    }

    private func make() async -> (LiveParticipantsRepository, RoutingTransport) {
        let transport = RoutingTransport()
        let repository = LiveParticipantsRepository(api: makeAPI(transport), context: SessionContext(user: me))
        return (repository, transport)
    }

    @Test func mapsTheProfileWithCalendarDaysAndThePendingFlag() async throws {
        let (repository, transport) = await make()
        await transport.set("GET api/participants/501", .json(info))
        await transport.set(
            "GET api/employee/u-alex/501/profile-change/last/is-Pending",
            .json(#"{"data":true,"success":true}"#)
        )
        let profile = try await repository.profile(id: 501)
        #expect(profile.name == "Jordan Lee" && profile.initials == "JL")
        #expect(profile.waiver == "CC")
        #expect(profile.email == nil)
        #expect(profile.planEnd == CalendarDate(year: 2027, month: 3, day: 31))
        #expect(profile.birthDate == CalendarDate(year: 1988, month: 6, day: 2))
        #expect(profile.changePending && profile.compliant && !profile.deactivated)
    }

    @Test func aFailedPendingCheckStillShowsTheProfile() async throws {
        let (repository, transport) = await make()
        await transport.set("GET api/participants/501", .json(info))
        let profile = try await repository.profile(id: 501)
        #expect(!profile.changePending)
    }

    @Test func aParticipantOutsideTheViewersRolesIsForbidden() async {
        let (repository, transport) = await make()
        await transport.set("GET api/participants/501", .status(403))
        await #expect(throws: WaiveraError.forbidden) { try await repository.profile(id: 501) }
    }

    @Test func openTasksReadEveryPageDropClosedOnesAndPutTheEarliestDueFirst() async throws {
        let (repository, transport) = await make()
        let first = [task(1, due: "2026-12-01"), task(2, due: nil), task(3, due: "2026-10-01", status: "Closed")]
        await transport.enqueue(
            "GET api/tasks/participant/501",
            .json(#"{"items":[\#(first.joined(separator: ","))],"totalCount":4}"#),
            .json(#"{"items":[\#(task(4, due: "2026-11-02"))],"totalCount":4}"#)
        )
        let tasks = try await repository.openTasks(id: 501)
        #expect(tasks.map(\.id) == [4, 1, 2])
        #expect(await transport.count("GET api/tasks/participant/501") == 2)
    }
}
