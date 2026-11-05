#if canImport(UIKit)
    import Foundation
    import WaiveraData

    /// Copy for Request time off. Values live in `Localizable.strings`.
    enum TimeOffStrings {
        static func text(_ key: String) -> String {
            NSLocalizedString(key, bundle: .module, comment: "")
        }

        static func format(_ key: String, _ arguments: String...) -> String {
            String(format: text(key), arguments: arguments)
        }

        /// "40 hrs", "1 hr", "1.5 hrs"; negative balances keep their sign.
        static func hours(minutes: Int) -> String {
            let hours = Double(minutes) / 60
            let number = hours.formatted(.number.precision(.fractionLength(0...2)))
            let key = abs(minutes) == 60 ? "profile.leave.hours.one" : "profile.leave.hours.other"
            return format(key, number)
        }

        static func tasks(_ count: Int) -> String {
            format(count == 1 ? "profile.leave.impactTasks.one" : "profile.leave.impactTasks.other", String(count))
        }

        static func balance(_ type: LeaveType) -> String {
            guard type.tracksBalance else { return text("profile.leave.noBalance") }
            guard let available = type.availableMinutes else { return text("profile.leave.balanceUnknown") }
            return format("profile.leave.available", hours(minutes: available))
        }

        static func block(_ block: LeaveBlock) -> String {
            switch block {
            case .weekend: text("profile.leave.blockWeekend")
            case .holiday: text("profile.leave.blockHoliday")
            case .overlap: text("profile.leave.blockOverlap")
            case .other: text("profile.leave.blockOther")
            }
        }

        static func failure(_ problem: LeaveSendProblem?) -> String {
            switch problem {
            case .notEnoughBalance: text("profile.leave.failedBalance")
            case .probation: text("profile.leave.failedProbation")
            case .weekend: text("profile.leave.blockWeekend")
            case .holiday: text("profile.leave.blockHoliday")
            case .noWorkdays: text("profile.leave.failedDates")
            case .overlap: text("profile.leave.blockOverlap")
            case .other, nil: text("profile.leave.failed")
            }
        }
    }
#endif
