#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Time-off balances: remaining days, a progress bar of the remaining share, the counts, the
    /// first three requests and how many more exist (08 §3).
    struct TimeOffCard: View {
        let overview: TimeOffOverview

        var body: some View {
            let fraction = TimeOffRules.remainingFraction(overview)
            SectionCard(title: ProfileStrings.timeOffTitle) {
                VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                    VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                        Text(ProfileFormat.days(overview.remainingDays))
                            .font(WaiveraFont.screenTitle)
                            .foregroundStyle(Palette.text)
                        Text(ProfileStrings.timeOffRemaining)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    ProgressView(value: fraction)
                        .tint(Palette.accent)
                        .background(Palette.surfaceMuted, in: Capsule())
                        .accessibilityLabel(
                            Text(ProfileStrings.timeOffProgress(percent: Int((fraction * 100).rounded())))
                        )
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.large) { counts }
                        VStack(alignment: .leading, spacing: Spacing.small) { counts }
                    }
                }
                .padding(Spacing.medium)
                ForEach(TimeOffRules.visibleEntries(overview)) { entry in
                    RowDivider()
                    TimeOffEntryRow(entry: entry)
                }
                let hidden = TimeOffRules.hiddenCount(overview)
                if hidden > 0 {
                    RowDivider()
                    Text(ProfileStrings.timeOffMore(hidden))
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(Spacing.medium)
                }
            }
        }

        @ViewBuilder private var counts: some View {
            stat(ProfileStrings.timeOffAllocated, overview.allocated)
            stat(ProfileStrings.timeOffUsed, overview.used)
            stat(ProfileStrings.timeOffPending, overview.pending)
        }

        private func stat(_ label: String, _ value: Double?) -> some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(value.map { ProfileFormat.days($0) } ?? ProfileStrings.missing)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(Palette.text)
                Text(label)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(value.map { ProfileFormat.days($0) } ?? ProfileStrings.missingSpoken))
        }
    }

    private struct TimeOffEntryRow: View {
        let entry: TimeOffEntry

        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.smallPlus) {
                    details.frame(maxWidth: .infinity, alignment: .leading)
                    badge
                }
                VStack(alignment: .leading, spacing: Spacing.small) {
                    details
                    badge
                }
            }
            .padding(.vertical, Spacing.smallPlus)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: ControlSize.minHitTarget)
            .accessibilityElement(children: .combine)
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(entry.leaveType ?? ProfileStrings.timeOffDefaultType)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(Palette.text)
                if let range = ProfileFormat.dateRange(start: entry.start, end: entry.end) {
                    Text(range)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }

        private var badge: some View {
            StatusBadge(ProfileStrings.status(entry.status), tone: TimeOffRules.tone(entry.status).badgeTone)
        }
    }

    /// Up to five employee files. Rows are plainly non-interactive: there is no authenticated file
    /// endpoint for them yet (08 §4), so they do not look tappable.
    struct EmployeeFilesCard: View {
        let files: [EmployeeFile]
        let zone: TimeZone

        var body: some View {
            SectionCard(title: ProfileStrings.filesTitle) {
                if files.isEmpty {
                    Text(ProfileStrings.filesEmpty)
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(Spacing.medium)
                } else {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        if index > 0 { RowDivider() }
                        HStack(spacing: Spacing.smallPlus) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(Palette.accent)
                                .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                                .background(
                                    Palette.accentSoft,
                                    in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                )
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                                Text(file.fileName ?? ProfileStrings.filesUntitled)
                                    .font(WaiveraFont.bodyEmphasis)
                                    .foregroundStyle(Palette.text)
                                if let added = file.addedAt {
                                    Text(ProfileStrings.filesAdded(ProfileFormat.date(of: added, in: zone)))
                                        .font(WaiveraFont.caption)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, Spacing.small)
                        .padding(.horizontal, Spacing.medium)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    /// Organization details: a read-only list with the same "—" fallback (08 §5).
    public struct OrganizationView: View {
        @Environment(\.dataEnvironment) private var data

        public init() {}

        public var body: some View {
            Group {
                if let data {
                    OrganizationScreen(model: ProfileModel(environment: data))
                } else {
                    OrganizationContentView(phase: .unavailable, organization: nil, onRetry: {})
                }
            }
            .background(Palette.background)
            .navigationTitle(ProfileStrings.organizationTitle)
        }
    }

    private struct OrganizationScreen: View {
        @State private var model: ProfileModel
        @State private var retryRequest = 0

        init(model: ProfileModel) {
            _model = State(initialValue: model)
        }

        var body: some View {
            OrganizationContentView(phase: model.phase, organization: model.content?.organization) {
                retryRequest += 1
            }
            .refreshable { await model.refresh() }
            .task { await model.run() }
            .task(id: retryRequest) {
                guard retryRequest > 0 else { return }
                await model.refresh()
            }
        }
    }

    struct OrganizationContentView: View {
        let phase: ProfileModel.Phase
        let organization: Organization?
        let onRetry: () -> Void

        var body: some View {
            ScrollView {
                switch phase {
                case .loading:
                    LoadingContent(isLoading: true) {
                        EmptyView()
                    } skeleton: {
                        ProfileSkeleton()
                    }
                case .failed(let error):
                    EmptyStateView.error(
                        title: ProfileStrings.organizationTitle,
                        message: error.userMessage,
                        onRetry: onRetry
                    )
                    .padding(.top, Spacing.extraLarge)
                case .unavailable, .loaded:
                    if let organization {
                        SectionCard(title: organization.name ?? ProfileStrings.organizationTitle) {
                            DetailRow(label: ProfileStrings.organizationName, value: organization.name)
                            RowDivider()
                            DetailRow(label: ProfileStrings.organizationAbbreviation, value: organization.abbreviation)
                            RowDivider()
                            DetailRow(label: ProfileStrings.organizationAddress, value: organization.address)
                            RowDivider()
                            DetailRow(label: ProfileStrings.organizationContact, value: organization.contactNumber)
                        }
                        .padding(Spacing.medium)
                    } else {
                        EmptyStateView(systemImage: "building.2", title: ProfileStrings.organizationUnavailable)
                            .padding(.top, Spacing.extraLarge)
                    }
                }
            }
        }
    }

    #if DEBUG
        #Preview("Light") {
            NavigationStack { OrganizationView() }.fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack {
                OrganizationContentView(phase: .loaded, organization: DemoData.make().organization, onRetry: {})
            }
            .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            ScrollView {
                if let timeOff = DemoData.make().profile.timeOff {
                    TimeOffCard(overview: timeOff).padding(Spacing.medium)
                }
            }
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
