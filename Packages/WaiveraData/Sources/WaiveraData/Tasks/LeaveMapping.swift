import Foundation
import WaiveraAPI

/// What a person asking for time off sees: leave types with balances, the server's check, and
/// refusals (Android `LeaveMapping`).
enum LeaveMapping {
    /// The name from the type list, the balance from the person's balances; the server's order.
    static func leaveTypes(_ types: [LeaveTypeResponse], balances: [LeaveBalanceResponse]?) -> [LeaveType] {
        types.compactMap { type -> LeaveType? in
            guard type.isActive != false, type.isDeleted != true, let id = type.id,
                let name = TaskMapping.trimmed(type.requestType)
            else { return nil }
            let balance = balances?.first { $0.id == id }
            let tracks = balance?.tracksBalance ?? false
            return LeaveType(
                id: id,
                name: name,
                tracksBalance: tracks,
                availableMinutes: tracks ? balance?.availableMinutes : nil
            )
        }
    }

    static func preview(_ dto: LeavePreviewResponse) -> LeavePreview {
        let requested = dto.requestedMinutes ?? 0
        // sprout_web: no requestable hours blocks the send even when the server forgets a code.
        let block: LeaveBlock? =
            if dto.isRequestable == true && requested > 0 {
                nil
            } else {
                switch dto.blockingCode {
                case "LEAVE_ON_WEEKEND": .weekend
                case "LEAVE_ON_HOLIDAY": .holiday
                case "LEAVE_OVERLAPS_EXISTING": .overlap
                default: .other
                }
            }
        return LeavePreview(
            requestedMinutes: requested,
            tracksBalance: dto.tracksBalance ?? false,
            beforeMinutes: dto.beforeMinutes,
            afterMinutes: dto.afterMinutes,
            block: block,
            impact: dto.intelligence.map(ApprovalMapping.impact)
        )
    }

    /// sprout_api `AddOrUpdateTimeOffAsync` and `ReserveAsync` refusals the person can act on.
    static func sendProblem(_ error: WaiveraError, code: String?) -> LeaveSendProblem? {
        if error == .conflict { return .holiday }
        guard error == .invalidRequest else { return nil }
        switch code {
        case "INSUFFICIENT_LEAVE_BALANCE": return .notEnoughBalance
        case "LEAVE_NOT_ALLOWED_DURING_PROBATION": return .probation
        case "LEAVE_ON_WEEKEND": return .weekend
        case "LEAVE_HAS_NO_WORKDAYS": return .noWorkdays
        // The overlap refusal carries no code; it is the one 400 a filled-in form still gets.
        case nil: return .overlap
        default: return .other
        }
    }

    /// The web sends instants as ISO text with milliseconds.
    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
