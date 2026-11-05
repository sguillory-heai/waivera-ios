import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TasksFeature

/// Mirrors Android `RequirementChecksTest` (web `WorkflowRequirementValidators`).
struct RequirementChecksTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 5) ?? DemoData.today

    private static func planDates(defaults: String? = nil) -> StageRequirement {
        StageRequirement(
            actionId: 7,
            key: "plan",
            actionType: StageRequirement.planDates,
            title: "New plan dates",
            description: nil,
            fields: [
                RequirementField(
                    key: StageRequirement.planStart,
                    label: "Start",
                    type: .date,
                    required: true,
                    defaultValue: defaults
                ),
                RequirementField(
                    key: StageRequirement.planEnd,
                    label: "End",
                    type: .date,
                    required: true,
                    defaultValue: nil
                ),
            ]
        )
    }

    private func check(_ start: String, _ end: String, plan: PlanDates? = nil) -> RequirementChecks.Result {
        RequirementChecks.check(
            Self.planDates(),
            values: [StageRequirement.planStart: start, StageRequirement.planEnd: end],
            plan: plan,
            today: Self.today
        )
    }

    @Test func emptyRequiredFieldsAreErrors() {
        let result = check("", " ")
        #expect(result.errors[StageRequirement.planStart]?.kind == .required)
        #expect(result.errors[StageRequirement.planEnd]?.kind == .required)
        #expect(result.warnings.isEmpty)
    }

    @Test func badDatesAndAnEndBeforeTheStartAreErrors() {
        #expect(check("2026-13-40", "2027-11-04").errors[StageRequirement.planStart]?.kind == .invalidDate)
        #expect(check("2026-11-05", "2026-11-04").errors[StageRequirement.planEnd]?.kind == .endBeforeStart)
    }

    @Test func aYearLongPlanStartingTheDayAfterTheLastOneHasNoWarnings() {
        let plan = PlanDates(start: nil, end: CalendarDate(year: 2026, month: 11, day: 4))
        let result = check("2026-11-05", "2027-11-04", plan: plan)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test func unusualDatesWarnWithTheExpectedDay() {
        let plan = PlanDates(start: nil, end: CalendarDate(year: 2026, month: 10, day: 31))
        let result = check("2026-11-05", "2027-11-30", plan: plan)
        #expect(result.warnings[StageRequirement.planStart] == RequirementIssue(
            kind: .expectedStart,
            date: CalendarDate(year: 2026, month: 11, day: 1)
        ))
        #expect(result.warnings[StageRequirement.planEnd] == RequirementIssue(
            kind: .expectedEnd,
            date: CalendarDate(year: 2027, month: 11, day: 4)
        ))
    }

    @Test func aStartOverAYearAgoWarns() {
        let result = check("2025-10-01", "2026-09-30")
        #expect(result.warnings[StageRequirement.planStart]?.kind == .overAYearAgo)
        #expect(result.warnings[StageRequirement.planEnd] == nil)
    }

    /// The year after a start just before spring-forward ends the day before, not a day off.
    @Test func expectedEndAcrossADaylightSavingChangeIsADayCount() {
        let result = check("2026-03-07", "2027-03-06")
        #expect(result.warnings.isEmpty)
    }

    @Test func initialValuesKeepOnlyTheDatePartOfADefault() {
        let values = RequirementChecks.initial([Self.planDates(defaults: "2026-11-05T00:00:00Z")])
        #expect(values[7]?[StageRequirement.planStart] == "2026-11-05")
        #expect(values[7]?[StageRequirement.planEnd] == "")
    }
}
