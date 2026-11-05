import Foundation
import WaiveraAPI

/// The details a reviewer reads before deciding time off, profile changes and training credit
/// (Android `ApprovalMapping`).
enum ApprovalMapping {
    private static let partialDay = "PARTIAL_DAY"
    private static let futureTaskReview = "FUTURE_TASK_REVIEW"
    private static let supervision = "SUPERVISION"
    private static let shortNoticeVacation = "SHORT_NOTICE_VACATION"
    private static let extendedSickLeave = "EXTENDED_SICK_LEAVE"
    private static let mask = "••••"
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt

    /// sprout_web `renderTimeOffDetails`: full days are UTC calendar dates, partial days instants.
    static func timeOff(_ dto: TimeOffDetailsResponse) -> TimeOffReview {
        let start = TaskMapping.instant(dto.timeOffStartDate)
        let end = TaskMapping.instant(dto.timeOffEndDate)
        let saved = intelligence(dto.intelligenceSnapshotJson)
        let current = intelligence(dto.currentIntelligenceJson)
        let hasSnapshot = !(dto.intelligenceSnapshotJson?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        var changed = false
        if let saved, let current { changed = visible(saved) != visible(current) }
        return TimeOffReview(
            leaveType: TaskMapping.trimmed(dto.typeOfLeave) ?? "",
            leaveTypeId: dto.typeOfLeaveId ?? 0,
            partialDay: dto.requestType?.uppercased() == partialDay,
            startDate: start.map { CalendarDate($0, in: utc) },
            endDate: end.map { CalendarDate($0, in: utc) },
            start: start,
            end: end,
            minutes: dto.durationMinutes ?? 0,
            note: TaskMapping.trimmed(dto.comment),
            impact: (current ?? saved).map(impact),
            impactChanged: changed,
            acknowledged: hasSnapshot
                ? dto.impactAcknowledgedAt != nil && dto.impactAcknowledgedRevision == dto.reviewRevision
                : nil
        )
    }

    private static func intelligence(_ raw: String?) -> LeaveIntelligenceResponse? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty, let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? WaiveraJSON.decoder().decode(LeaveIntelligenceResponse.self, from: data)
    }

    private static func isVisible(_ code: String) -> Bool { code != futureTaskReview && !code.contains(supervision) }

    private struct Visible: Equatable {
        var overdue: Int
        var during: Int
        var codes: [String]
    }

    private static func visible(_ review: LeaveIntelligenceResponse) -> Visible {
        Visible(
            overdue: review.overdueCount ?? 0,
            during: review.dueDuringLeaveCount ?? 0,
            codes: (review.warnings ?? []).map { $0.code ?? "" }.filter(isVisible).sorted()
        )
    }

    static func impact(_ review: LeaveIntelligenceResponse) -> LeaveImpact {
        let codes = (review.warnings ?? []).compactMap(\.code)
        // The phone words the codes it knows itself rather than showing the server's text.
        return LeaveImpact(
            dueBefore: review.overdueCount ?? 0,
            dueDuring: review.dueDuringLeaveCount ?? 0,
            shortNotice: codes.contains(shortNoticeVacation),
            extendedSick: codes.contains(extendedSickLeave)
        )
    }

    /// sprout_web `renderChangeDiff`, without the web's empty Waiver ID and with SSN digits masked.
    static func profile(_ dto: ParticipantChangeResponse) -> [ProfileField] {
        guard let old = dto.orignalProfile, let new = dto.newProfileChanegs else { return [] }
        func text(_ value: String?) -> String? { TaskMapping.trimmed(value) }
        func date(_ value: String?) -> String? { TaskMapping.date(value)?.isoString }
        func id(_ value: Int?) -> String? { value.flatMap { $0 == 0 ? nil : String($0) } }
        let fields: [(ProfileField.Field, String?, String?)] = [
            (.dateOfBirth, date(old.dateOfBirth), date(new.dateOfBirth)),
            (.firstName, text(old.firstName), text(new.firstName)),
            (.lastName, text(old.lastName), text(new.lastName)),
            (.email, text(old.email), text(new.email)),
            (.mobile, text(old.mobileNumber), text(new.mobileNumber)),
            (.waiver, text(old.waiverName), text(new.waiverName)),
            (.waiverId, id(old.waiverId), id(new.waiverId)),
            (.ssn, text(old.participantSsnLast4), text(new.participantSsnLast4)),
            (.certification, date(old.certificationDate), date(new.certificationDate)),
            (.cpocStart, date(old.cpocDate), date(new.cpocDate)),
            (.cpocEnd, date(old.cpocEndDate), date(new.cpocEndDate)),
        ]
        return fields.compactMap { field, previous, requested in
            guard previous != nil || requested != nil else { return nil }
            let changed = previous != requested
            if field == .ssn {
                return ProfileField(
                    field: field,
                    previous: previous.map { _ in mask },
                    requested: requested.map { _ in mask },
                    changed: changed
                )
            }
            return ProfileField(field: field, previous: previous, requested: requested, changed: changed)
        }
    }

    static func balance(_ dto: LeaveBalanceResponse) -> LeaveBalance {
        LeaveBalance(
            leaveTypeId: dto.id ?? 0,
            tracksBalance: dto.tracksBalance ?? false,
            availableMinutes: dto.availableMinutes ?? 0
        )
    }

    static func training(requestId: Int, _ dto: TrainingCreditResponse) -> TrainingCredit {
        let blockedText = dto.approvalBlockedReason?.lowercased() ?? ""
        let status = dto.status?.trimmingCharacters(in: .whitespaces) ?? ""
        let pending = status.isEmpty || status.lowercased() == "pending"
        let blocked: TrainingBlock? =
            if !pending || blockedText.isEmpty {
                nil
            } else if blockedText.contains("your own") {
                .ownCredit
            } else if blockedText.contains("no eligible reviewer") {
                .noReviewer
            } else {
                .notReviewer
            }
        let submitter = TaskMapping.trimmed(dto.submittedByName)
        return TrainingCredit(
            requestId: requestId,
            course: TaskMapping.trimmed(dto.courseTitle) ?? "",
            employeeName: TaskMapping.trimmed(dto.employeeName) ?? "",
            trainer: TaskMapping.trimmed(dto.trainerName),
            provider: TaskMapping.trimmed(dto.provider),
            completed: TaskMapping.date(dto.completedDate),
            hours: dto.hours ?? 0,
            pending: pending,
            revision: dto.revision,
            canApprove: dto.canApprove ?? false,
            needsApproveReason: dto.requiresOverrideReason ?? false,
            uploadedBy: (dto.uploadedForEmployee ?? false) ? submitter : nil,
            // The server words these for the web; the phone says the same in its own strings.
            blocked: blocked,
            reviewOnWeb: dto.standaloneCreditId != nil
        )
    }
}
