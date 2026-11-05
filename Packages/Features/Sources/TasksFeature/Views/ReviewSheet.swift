#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// What a review sheet loads after it opens: the balance for time off, the credit for training.
    struct ReviewExtras {
        var balance: Loadable<BalanceChange?> = .ready(nil)
        var training: Loadable<TrainingCredit> = .loading
        var openingCertificate = false
    }

    struct ReviewActions {
        var approve: () -> Void
        var reject: () -> Void
        var openTask: (() -> Void)?
        var retry: () -> Void = {}
        var openCertificate: () -> Void = {}
        var openWeb: () -> Void = {}
    }

    /// The review (Android `ReviewFields`): who asked and when, what changes and why, then the
    /// decision. The details scroll and the buttons stay pinned under them, so a long note never
    /// pushes Approve out of reach. Each decision is confirmed on its own sheet.
    struct ReviewSheet: View {
        let item: RequestItem
        var extras = ReviewExtras()
        let actions: ReviewActions

        var body: some View {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                        Text(item.reviewTitle)
                            .waiveraTextStyle(.titleLarge, weight: .bold)
                            .foregroundStyle(Palette.text)
                            .accessibilityAddTraits(.isHeader)
                        ReviewRequester(item: item)
                        details
                    }
                    .padding(Spacing.gutter)
                }
                ReviewDecisions(item: item, training: extras.training, actions: actions)
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.medium)
            }
            .background(Palette.surface)
        }

        @ViewBuilder
        private var details: some View {
            switch item.change {
            case .timeOff(let change):
                ReviewTimeOff(item: item, change: change, balance: extras.balance, onRetry: actions.retry)
            case .profile(let changed, let unchanged):
                ReviewProfile(changed: changed, unchanged: unchanged)
            case .training:
                ReviewTraining(
                    training: extras.training,
                    opening: extras.openingCertificate,
                    onRetry: actions.retry,
                    onOpenCertificate: actions.openCertificate
                )
            default:
                ReviewTaskRequest(item: item, onOpenTask: actions.openTask)
            }
        }
    }

    /// The requester's avatar and name, and when they asked.
    struct ReviewRequester: View {
        let item: RequestItem

        var body: some View {
            HStack(spacing: Spacing.mediumSmall) {
                AvatarView(name: item.request.requesterName, size: ControlSize.avatarMedium)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(item.request.requesterName)
                        .waiveraTextStyle(.titleSmall)
                        .foregroundStyle(Palette.text)
                    if let asked = item.asked {
                        Text(TasksStrings.format("tasks.review.requested", asked.text.lowercasedFirstWord))
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Approve and Reject, or the training credit's own wording; a credit the phone can't
    /// decide offers the web instead.
    struct ReviewDecisions: View {
        let item: RequestItem
        let training: Loadable<TrainingCredit>
        let actions: ReviewActions

        var body: some View {
            if item.request.kind != .trainingCredit {
                buttons(approve: "tasks.approve", reject: "tasks.reject")
            } else if let credit = training.value {
                if credit.decidable {
                    buttons(approve: "tasks.review.approveCredit", reject: "tasks.review.rejectSubmission")
                } else if credit.reviewOnWeb {
                    WaiveraButton(
                        TasksStrings.text("tasks.review.onWeb"),
                        variant: .secondary,
                        size: .large,
                        systemImage: "arrow.up.right.square",
                        fillsWidth: true,
                        action: actions.openWeb
                    )
                }
            }
        }

        private func buttons(approve: String, reject: String) -> some View {
            VStack(spacing: Spacing.mediumSmall) {
                WaiveraButton(
                    TasksStrings.text(approve),
                    size: .large,
                    systemImage: "checkmark",
                    fillsWidth: true,
                    action: actions.approve
                )
                WaiveraButton(
                    TasksStrings.text(reject),
                    variant: .destructiveOutline,
                    size: .large,
                    systemImage: "xmark",
                    fillsWidth: true,
                    action: actions.reject
                )
            }
        }
    }

    extension String {
        /// "Today, 9:12 AM" reads "today, 9:12 AM" after "Requested".
        var lowercasedFirstWord: String { prefix(1).lowercased() + dropFirst() }
    }
#endif
