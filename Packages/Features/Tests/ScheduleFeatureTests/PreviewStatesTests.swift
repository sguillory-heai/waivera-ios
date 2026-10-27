import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ScheduleFeature

/// The preview and snapshot states are built through the production builders, so each named
/// state must really show what its name says.
@Suite("Preview states")
struct PreviewStatesTests {
    typealias ScheduleCheck = @Sendable (ScheduleUIState) -> Bool
    typealias EventCheck = @Sendable (EventDetailsUI) -> Bool

    static let scheduleChecks: [SchedulePreviewStates.Schedule: ScheduleCheck] = [
        .month: { $0.view == .month && $0.cells.count == 42 && hasRows($0.agenda) },
        .week: { $0.view == .week && $0.cells.count == 7 && hasRows($0.agenda) },
        .day: { $0.view == .day && hasRows($0.agenda) },
        .loading: { $0.agenda == .loading },
        .empty: { $0.agenda == .empty },
        .error: { $0.agenda == .error(.server(statusCode: 503)) },
        .refreshFailed: { $0.feedNotice != nil && hasRows($0.agenda) },
        .milestonesFailed: { $0.milestonesFailed && hasRows($0.agenda) },
        .fallbackZone: { $0.zoneIdentifier == "America/Chicago" && $0.zoneNotice != nil },
        .otherDay: { !$0.isTodaySelected && $0.cells.count == 42 },
    ]

    static let eventChecks: [SchedulePreviewStates.Event: EventCheck] = [
        .pendingInvitation: { $0.invitation?.response == .pending && $0.invitation?.canChange == true },
        .accepted: { $0.invitation?.response == .accepted && $0.invitation?.phase == .undoWindow },
        .saving: { $0.invitation?.phase == .saving },
        .responseFailed: { $0.invitationFailure != nil },
        .organizer: { $0.isOrganizer && $0.invitation == nil },
        .joinOpen: { $0.join?.state == .open },
        .joinFailed: { $0.joinError != nil },
        .started: { $0.invitation?.canChange == false },
        .allDay: { $0.join == nil },
        .refreshFailed: { $0.refreshNotice != nil },
    ]

    static func hasRows(_ agenda: AgendaState) -> Bool {
        if case .content(let rows) = agenda { return !rows.isEmpty }
        return false
    }

    @Test(arguments: SchedulePreviewStates.Schedule.allCases)
    func scheduleStateShowsWhatItsNameSays(_ variant: SchedulePreviewStates.Schedule) throws {
        let check = try #require(Self.scheduleChecks[variant])
        #expect(check(SchedulePreviewStates.schedule(variant)))
    }

    @Test(arguments: Array(eventChecks.keys))
    func loadedEventStateShowsWhatItsNameSays(_ variant: SchedulePreviewStates.Event) throws {
        let check = try #require(Self.eventChecks[variant])
        guard case .loaded(let details) = SchedulePreviewStates.event(variant) else {
            Issue.record("\(variant) should load a demo event")
            return
        }
        #expect(check(details))
    }

    @Test func screenLevelEventStatesAndEveryVariantIsChecked() {
        #expect(SchedulePreviewStates.event(.loading) == .loading)
        #expect(SchedulePreviewStates.event(.notFound) == .notFound)
        #expect(SchedulePreviewStates.event(.error) == .error(.server(statusCode: 503)))
        let screenLevel: Set<SchedulePreviewStates.Event> = [.loading, .notFound, .error]
        #expect(Set(Self.eventChecks.keys).union(screenLevel) == Set(SchedulePreviewStates.Event.allCases))
    }
}
