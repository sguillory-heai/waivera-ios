#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Time off and its cancellation (sprout_web `renderTimeOffDetails`): the dates, leave type,
    /// balance and note, then the task review the web shows beside it.
    struct ReviewTimeOff: View {
        let item: RequestItem
        let change: TimeOffChange
        let balance: Loadable<BalanceChange?>
        let onRetry: () -> Void

        var body: some View {
            SheetCardGroup {
                FactRow(systemImage: "calendar", label: TasksStrings.text("tasks.review.dates")) {
                    FactValue(text: change.dates.text)
                    let length = RequestItems.hours(minutes: change.minutes)
                    FactNote(
                        text: change.times.map { TasksStrings.format("tasks.review.partialDay", $0.text, length) }
                            ?? TasksStrings.format("tasks.review.fullDays", length)
                    )
                }
                if !change.leaveType.isEmpty {
                    InsetDivider()
                    FactRow(systemImage: "number", label: TasksStrings.text("tasks.review.leaveType")) {
                        FactValue(text: change.leaveType)
                    }
                }
                balanceRow
                if let note = item.request.timeOff?.note {
                    InsetDivider()
                    FactRow(systemImage: "text.bubble", label: TasksStrings.text("tasks.review.note")) {
                        ActivityNote(text: note)
                    }
                }
            }
            if let timeOff = item.request.timeOff {
                ReviewImpact(name: item.request.requesterName, timeOff: timeOff)
            }
        }

        @ViewBuilder
        private var balanceRow: some View {
            let label = TasksStrings.text("tasks.review.balance")
            switch balance {
            case .loading:
                InsetDivider()
                FactRow(systemImage: "clock", label: label) {
                    SkeletonBlock(width: ControlSize.avatarLarge * 2, height: ControlSize.skeletonLine)
                }
            case .ready(let change?):
                InsetDivider()
                FactRow(systemImage: "clock", label: label) {
                    let before = RequestItems.hours(minutes: change.before)
                    let after = RequestItems.hours(minutes: change.after)
                    HStack(spacing: Spacing.extraSmall) {
                        FactValue(text: before)
                        FactValue(text: TasksStrings.text("tasks.review.balanceArrow"))
                        // The web marks a balance that would go below zero in red; it does not block approval.
                        FactValue(text: after, color: change.after < 0 ? Palette.dangerText : Palette.text)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TasksStrings.format("tasks.review.balanceSpoken", before, after)))
                    FactNote(
                        text: TasksStrings.text(
                            self.change.cancellation ? "tasks.review.balanceAfterCancel" : "tasks.review.balanceAfter"
                        )
                    )
                }
            case .ready(.none):
                EmptyView()
            case .failed:
                InsetDivider()
                Button(action: onRetry) {
                    FactRow(systemImage: "clock", label: label) {
                        FactValue(text: TasksStrings.text("tasks.review.balanceFailed"))
                        FactNote(text: TasksStrings.text("tasks.review.balanceRetry"))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.card))
            }
        }
    }

    /// sprout_web `LeaveImpactSummary`, with the acknowledgement line from the review modal.
    struct ReviewImpact: View {
        let name: String
        let timeOff: TimeOffReview

        var body: some View {
            if let impact = timeOff.impact {
                if impact.shortNotice {
                    BannerView(
                        .info,
                        title: TasksStrings.text("tasks.review.shortNoticeTitle"),
                        message: TasksStrings.text("tasks.review.shortNotice")
                    )
                }
                let total = impact.dueBefore + impact.dueDuring
                BannerView(
                    total > 0 ? .warning : .info,
                    title: total > 0
                        ? TasksStrings.plural("tasks.review.impactTasks", total, firstName)
                        : TasksStrings.text("tasks.review.impactNone"),
                    message: details(impact, total: total)
                )
            } else if timeOff.acknowledged != nil {
                BannerView(.warning, message: TasksStrings.text("tasks.review.impactUnavailable"))
            }
        }

        private var firstName: String {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        }

        private func details(_ impact: LeaveImpact, total: Int) -> String {
            var lines: [String] = []
            if total > 0 {
                lines.append(
                    TasksStrings.format(
                        "tasks.review.impactCounts",
                        String(impact.dueBefore),
                        String(impact.dueDuring)
                    )
                )
            }
            if timeOff.impactChanged { lines.append(TasksStrings.text("tasks.review.impactChanged")) }
            if impact.extendedSick { lines.append(TasksStrings.text("tasks.review.extendedSick")) }
            switch timeOff.acknowledged {
            case true?: lines.append(TasksStrings.text("tasks.review.impactAcknowledged"))
            case false?: lines.append(TasksStrings.text("tasks.review.impactNotAcknowledged"))
            case nil: break
            }
            return lines.joined(separator: " ")
        }
    }
#endif
