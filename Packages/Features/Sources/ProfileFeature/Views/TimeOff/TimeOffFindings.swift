#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The local issue, the past-date note, then what the server said: blocked, balance, impact.
    struct TimeOffFindings: View {
        let state: TimeOffFormState
        let onRetryCheck: () -> Void

        var body: some View {
            if state.issue == .tooShort || state.issue == .tooLong {
                BannerView(
                    .error,
                    title: TimeOffStrings.text("profile.leave.issueTitle"),
                    message: TimeOffStrings.text(
                        state.issue == .tooShort ? "profile.leave.issueShort" : "profile.leave.issueLong"
                    )
                )
            }
            if state.past {
                BannerView(.warning, message: TimeOffStrings.text("profile.leave.past"))
            }
            switch state.check {
            case .idle:
                EmptyView()
            case .checking:
                Text(TimeOffStrings.text("profile.leave.checking"))
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
            case .failed:
                BannerView(
                    .error,
                    message: TimeOffStrings.text("profile.leave.checkFailed"),
                    actionTitle: TimeOffStrings.text("profile.leave.tryAgain"),
                    action: onRetryCheck
                )
            case .ready(let preview):
                if let block = preview.block {
                    BannerView(
                        .error,
                        title: TimeOffStrings.text("profile.leave.blockTitle"),
                        message: TimeOffStrings.block(block)
                    )
                } else {
                    TimeOffBalance(preview: preview)
                    if state.overBalance {
                        BannerView(
                            .error,
                            title: TimeOffStrings.text("profile.leave.overTitle"),
                            message: TimeOffStrings.format(
                                "profile.leave.over",
                                TimeOffStrings.hours(minutes: preview.requestedMinutes),
                                TimeOffStrings.hours(minutes: preview.beforeMinutes ?? 0)
                            )
                        )
                    }
                    if let impact = preview.impact { impactBanner(impact) }
                }
            }
        }

        /// sprout_web `LeaveImpactSummary` in the request modal, with its advisory line.
        private func impactBanner(_ impact: LeaveImpact) -> some View {
            let total = impact.dueBefore + impact.dueDuring
            var details: [String] = []
            if impact.shortNotice { details.append(TimeOffStrings.text("profile.leave.shortNotice")) }
            if impact.extendedSick { details.append(TimeOffStrings.text("profile.leave.extendedSick")) }
            details.append(TimeOffStrings.text("profile.leave.impactAdvice"))
            return BannerView(
                total > 0 || impact.shortNotice ? .warning : .info,
                title: total > 0 ? TimeOffStrings.tasks(total) : TimeOffStrings.text("profile.leave.impactNone"),
                message: details.joined(separator: " ")
            )
        }
    }

    /// The balance now and after this request, and the hours it asks for.
    struct TimeOffBalance: View {
        let preview: LeavePreview

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                if preview.tracksBalance, let before = preview.beforeMinutes, let after = preview.afterMinutes {
                    let now = TimeOffStrings.hours(minutes: before)
                    let later = TimeOffStrings.hours(minutes: after)
                    HStack(spacing: Spacing.small) {
                        figure(TimeOffStrings.text("profile.leave.now"), now, color: Palette.text)
                        Text(TimeOffStrings.text("profile.leave.arrow"))
                            .waiveraTextStyle(.fieldValue)
                            .foregroundStyle(Palette.textSecondary)
                        // Below zero reads in red, as on the web.
                        figure(
                            TimeOffStrings.text("profile.leave.after"),
                            later,
                            color: after < 0 ? Palette.dangerText : Palette.accent
                        )
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TimeOffStrings.format("profile.leave.balanceSpoken", now, later)))
                }
                Text(
                    TimeOffStrings.format(
                        "profile.leave.inRequest",
                        TimeOffStrings.hours(minutes: preview.requestedMinutes)
                    )
                )
                .waiveraTextStyle(.bodySmall)
                .foregroundStyle(Palette.textSecondary)
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheetCard()
        }

        private func figure(_ label: String, _ value: String, color: Color) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .waiveraTextStyle(.kicker)
                    .foregroundStyle(Palette.textSecondary)
                Text(value)
                    .waiveraTextStyle(.fieldValue)
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Every leave type the agency has, searchable past six, each with the person's balance.
    struct LeaveTypeList: View {
        private static let searchFrom = 6

        let types: [LeaveType]
        let selectedId: Int?
        let onPick: (Int) -> Void

        @State private var query = ""

        private var shown: [LeaveType] {
            let needle = query.trimmingCharacters(in: .whitespaces)
            return needle.isEmpty ? types : types.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                    Text(TimeOffStrings.text("profile.leave.leaveType"))
                        .waiveraTextStyle(.titleLarge, weight: .bold)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    if types.count > Self.searchFrom {
                        SearchField(
                            TimeOffStrings.text("profile.leave.findType"),
                            placeholder: TimeOffStrings.text("profile.leave.search"),
                            query: $query,
                            identifier: "profile.leave.search"
                        )
                    }
                    SheetCardGroup {
                        if shown.isEmpty {
                            Text(TimeOffStrings.text("profile.leave.noMatch"))
                                .waiveraTextStyle(.bodyMedium)
                                .foregroundStyle(Palette.textSecondary)
                                .padding(Spacing.medium)
                        }
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, type in
                            if index > 0 { InsetDivider(inset: Spacing.medium) }
                            row(type)
                        }
                    }
                }
                .padding(Spacing.gutter)
            }
            .background(Palette.surface)
            .presentationDetents([.medium, .large])
        }

        private func row(_ type: LeaveType) -> some View {
            let selected = type.id == selectedId
            let empty = type.tracksBalance && (type.availableMinutes ?? 1) <= 0
            return Button {
                onPick(type.id)
            } label: {
                HStack(spacing: Spacing.small) {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(type.name)
                            .waiveraTextStyle(.titleSmall)
                            .foregroundStyle(Palette.text)
                        Text(TimeOffStrings.balance(type))
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(empty ? Palette.dangerText : Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if selected {
                        WaiveraIcon(systemName: "checkmark")
                            .foregroundStyle(Palette.accent)
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .frame(minHeight: ControlSize.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.row))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
#endif
