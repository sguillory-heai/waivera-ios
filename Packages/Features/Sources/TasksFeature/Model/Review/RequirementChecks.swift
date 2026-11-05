import Foundation
import WaiveraAPI
import WaiveraData

/// sprout_web `WorkflowRequirementValidators`: required fields for every requirement, and for new
/// plan (CPOC) dates the date rules and the "expected date" warnings a reviewer confirms past.
/// "Today" is the employee's saved-zone day.
enum RequirementChecks {
    struct Result: Equatable {
        var errors: [String: RequirementIssue]
        var warnings: [String: RequirementIssue]
    }

    private static let isoDateLength = 10

    static func check(
        _ requirement: StageRequirement,
        values: [String: String],
        plan: PlanDates?,
        today: CalendarDate
    ) -> Result {
        var errors = required(requirement, values: values)
        var warnings: [String: RequirementIssue] = [:]
        if requirement.isPlanDates { planDates(values, plan: plan, today: today, &errors, &warnings) }
        return Result(errors: errors, warnings: errors.isEmpty ? warnings : [:])
    }

    /// The fields' starting values: the server's defaults, as the web fills them.
    static func initial(_ requirements: [StageRequirement]) -> [Int: [String: String]] {
        var values: [Int: [String: String]] = [:]
        for requirement in requirements {
            var fields: [String: String] = [:]
            for field in requirement.fields {
                let value = field.defaultValue ?? ""
                // A date default may carry a time; the field holds the date part only.
                fields[field.key] = field.type == .date ? String(value.prefix(isoDateLength)) : value
            }
            values[requirement.actionId] = fields
        }
        return values
    }

    static func date(_ value: String?) -> CalendarDate? {
        guard let value, value.count == isoDateLength else { return nil }
        return CalendarDate(parsing: value)
    }

    private static func required(
        _ requirement: StageRequirement,
        values: [String: String]
    ) -> [String: RequirementIssue] {
        var issues: [String: RequirementIssue] = [:]
        for field in requirement.fields where field.required {
            if (values[field.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                issues[field.key] = RequirementIssue(kind: .required)
            }
        }
        return issues
    }

    private static func planDates(
        _ values: [String: String],
        plan: PlanDates?,
        today: CalendarDate,
        _ errors: inout [String: RequirementIssue],
        _ warnings: inout [String: RequirementIssue]
    ) {
        let startText = values[StageRequirement.planStart] ?? ""
        let endText = values[StageRequirement.planEnd] ?? ""
        let start = date(startText)
        let end = date(endText)
        if !startText.trimmingCharacters(in: .whitespaces).isEmpty, start == nil {
            errors[StageRequirement.planStart] = RequirementIssue(kind: .invalidDate)
        }
        if !endText.trimmingCharacters(in: .whitespaces).isEmpty, end == nil {
            errors[StageRequirement.planEnd] = RequirementIssue(kind: .invalidDate)
        }
        if let start, let end, end < start {
            errors[StageRequirement.planEnd] = RequirementIssue(kind: .endBeforeStart)
        }
        guard errors.isEmpty else { return }
        let yearAgo = today.addingMonths(-12)
        if let start, start < yearAgo { warnings[StageRequirement.planStart] = RequirementIssue(kind: .overAYearAgo) }
        if let end, end < yearAgo { warnings[StageRequirement.planEnd] = RequirementIssue(kind: .overAYearAgo) }
        if let start, let expected = plan?.end?.adding(days: 1), start != expected {
            warnings[StageRequirement.planStart] = RequirementIssue(kind: .expectedStart, date: expected)
        }
        if let start, let end {
            let expected = start.addingMonths(12).adding(days: -1)
            if end != expected {
                warnings[StageRequirement.planEnd] = RequirementIssue(kind: .expectedEnd, date: expected)
            }
        }
    }
}
