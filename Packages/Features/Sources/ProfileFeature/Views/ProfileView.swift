#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The signed-in user's profile, from the avatar menu.
    public struct ProfileView: View {
        @Environment(\.dataEnvironment) private var data
        let onOpenOrganization: () -> Void
        let onOpenSettings: () -> Void

        public init(
            onOpenOrganization: @escaping () -> Void,
            onOpenSettings: @escaping () -> Void
        ) {
            self.onOpenOrganization = onOpenOrganization
            self.onOpenSettings = onOpenSettings
        }

        public var body: some View {
            Group {
                if let data {
                    ProfileScreen(
                        model: ProfileModel(environment: data),
                        onOpenOrganization: onOpenOrganization,
                        onOpenSettings: onOpenSettings
                    )
                } else {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        title: ProfileStrings.unavailableTitle
                    )
                }
            }
            .background(Palette.background)
            .navigationTitle(ProfileStrings.title)
        }
    }

    private struct ProfileScreen: View {
        @State private var model: ProfileModel
        @State private var refreshRequest = 0
        let onOpenOrganization: () -> Void
        let onOpenSettings: () -> Void

        init(model: ProfileModel, onOpenOrganization: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
            _model = State(initialValue: model)
            self.onOpenOrganization = onOpenOrganization
            self.onOpenSettings = onOpenSettings
        }

        var body: some View {
            ProfileContentView(
                state: ProfileDisplayState(model: model),
                onRetry: { refreshRequest += 1 },
                onOpenOrganization: onOpenOrganization,
                onOpenSettings: onOpenSettings
            )
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.phase != .unavailable {
                        RefreshToolbarButton(
                            title: ProfileStrings.refresh,
                            busyTitle: ProfileStrings.refreshing,
                            isRefreshing: model.isRefreshing
                        ) { refreshRequest += 1 }
                    }
                }
            }
            .task { await model.run() }
            .task(id: refreshRequest) {
                guard refreshRequest > 0 else { return }
                await model.refresh()
            }
        }
    }

    /// Everything the profile content shows, as plain values for previews and snapshots.
    struct ProfileDisplayState {
        var phase: ProfileModel.Phase
        var user: CurrentUser?
        var content: OwnProfile?
        var displayName: String?
        var celebration: Celebration?
        var timeZone: TimeZone
        var isDeviceZone: Bool
        var refreshError: WaiveraError?

        @MainActor
        init(model: ProfileModel) {
            phase = model.phase
            user = model.user
            content = model.content
            displayName = model.displayName
            celebration = model.celebration
            let zone = ProfileText.timeZone(profile: model.content?.profile, user: model.user)
            timeZone = zone.zone
            isDeviceZone = zone.isDevice
            refreshError = model.refreshError
        }

        init(
            phase: ProfileModel.Phase,
            user: CurrentUser?,
            content: OwnProfile?,
            celebration: Celebration? = nil,
            refreshError: WaiveraError? = nil
        ) {
            self.phase = phase
            self.user = user
            self.content = content
            displayName = ProfileText.displayName(profile: content?.profile, user: user)
            self.celebration = celebration
            let zone = ProfileText.timeZone(profile: content?.profile, user: user)
            timeZone = zone.zone
            isDeviceZone = zone.isDevice
            self.refreshError = refreshError
        }
    }

    /// The profile screen body for one state. Stateless: previews and snapshots build it directly.
    struct ProfileContentView: View {
        let state: ProfileDisplayState
        let onRetry: () -> Void
        let onOpenOrganization: () -> Void
        let onOpenSettings: () -> Void

        var body: some View {
            switch state.phase {
            case .unavailable:
                ScrollView {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        title: ProfileStrings.unavailableTitle,
                        message: ProfileStrings.unavailableMessage
                    )
                    .padding(.top, Spacing.extraLarge)
                }
            case .failed(let error):
                ScrollView {
                    EmptyStateView.error(title: ProfileStrings.errorTitle, message: error.userMessage, onRetry: onRetry)
                        .padding(.top, Spacing.extraLarge)
                }
            case .loading, .loaded:
                LoadingContent(isLoading: state.phase == .loading) {
                    loaded
                } skeleton: {
                    ScrollView { ProfileSkeleton() }
                }
            }
        }

        private var loaded: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    if state.refreshError != nil {
                        RefreshFailedNotice(message: ProfileStrings.refreshFailed, onRetry: onRetry)
                    }
                    ProfileIdentityCard(state: state)
                    ProfilePersonalSection(state: state)
                    ProfileProfessionalSection(profile: state.content?.profile)
                    if let timeOff = state.content?.timeOff, TimeOffRules.hasContent(timeOff) {
                        TimeOffCard(overview: timeOff)
                    }
                    EmployeeFilesCard(
                        files: ProfileSections.visibleFiles(state.content?.files ?? []),
                        zone: state.timeZone
                    )
                    ProfileLinksSection(
                        organization: state.content?.organization,
                        onOpenOrganization: onOpenOrganization,
                        onOpenSettings: onOpenSettings
                    )
                }
                .padding(Spacing.medium)
            }
            .waiveraHaptic(.failure, trigger: state.refreshError) { _, new in new != nil }
        }
    }

    private struct ProfileIdentityCard: View {
        let state: ProfileDisplayState

        var body: some View {
            let name = state.displayName ?? ProfileStrings.unknownPerson
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Spacing.medium) {
                    avatar(name); identity(name)
                }
                VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                    avatar(name); identity(name)
                }
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }

        private func avatar(_ name: String) -> some View {
            PersonAvatar(
                userID: state.user?.id,
                name: name,
                size: ControlSize.avatarLarge,
                celebration: state.celebration
            )
        }

        private func identity(_ name: String) -> some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(name)
                    .font(WaiveraFont.screenTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                if let title = ProfileText.jobTitle(state.content?.profile) {
                    Text(title)
                        .font(WaiveraFont.subtitle)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let email = state.content?.profile?.email ?? state.user?.email {
                    Text(email)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let celebration = state.celebration {
                    Label(ProfileStrings.celebrationSentence(celebration, name: name), systemImage: "party.popper.fill")
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.milestone)
                }
            }
        }
    }

    private struct ProfilePersonalSection: View {
        let state: ProfileDisplayState

        var body: some View {
            let profile = state.content?.profile
            SectionCard(title: ProfileStrings.personal) {
                DetailRow(label: ProfileStrings.email, value: profile?.email ?? state.user?.email)
                RowDivider()
                DetailRow(label: ProfileStrings.phone, value: profile?.phoneNumber)
                RowDivider()
                DetailRow(label: ProfileStrings.address, value: profile?.address)
                RowDivider()
                DetailRow(label: ProfileStrings.timeZone, value: zoneText)
            }
        }

        private var zoneText: String {
            if state.isDeviceZone { return ProfileStrings.timeZoneDevice }
            return ProfileStrings.timeZoneValue(
                name: ProfileFormat.zoneName(state.timeZone),
                identifier: state.timeZone.identifier
            )
        }
    }

    private struct ProfileProfessionalSection: View {
        let profile: EmployeeProfile?

        var body: some View {
            SectionCard(title: ProfileStrings.professional) {
                DetailRow(
                    label: ProfileStrings.hireDate,
                    value: (profile?.hireDate ?? profile?.joinDate).map { ProfileFormat.date($0) }
                )
                RowDivider()
                DetailRow(label: ProfileStrings.positions, value: ProfileText.joined(profile?.positions ?? []))
                RowDivider()
                DetailRow(label: ProfileStrings.officeLocations, value: ProfileText.joined(profile?.regions ?? []))
                RowDivider()
                DetailRow(label: ProfileStrings.reportsTo, value: ProfileText.joined(profile?.managers ?? []))
                RowDivider()
                DetailRow(label: ProfileStrings.birthday, value: profile?.birthday.map { ProfileFormat.birthday($0) })
            }
        }
    }

    private struct ProfileLinksSection: View {
        let organization: Organization?
        let onOpenOrganization: () -> Void
        let onOpenSettings: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                Button(action: onOpenOrganization) {
                    ListRow(
                        title: ProfileStrings.organizationTitle,
                        subtitle: organization?.name ?? ProfileStrings.organizationUnavailable,
                        showsChevron: true
                    ) {
                        IconTile(systemImage: "building.2.fill")
                    }
                }
                .buttonStyle(.pressScale)
                RowDivider()
                Button(action: onOpenSettings) {
                    ListRow(
                        title: ProfileStrings.settingsRow,
                        subtitle: ProfileStrings.settingsRowDetail,
                        showsChevron: true
                    ) {
                        IconTile(systemImage: "gearshape.fill")
                    }
                }
                .buttonStyle(.pressScale)
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    #if DEBUG
        @MainActor private func previewState(_ phase: ProfileModel.Phase) -> ProfileDisplayState {
            let data = DemoData.make()
            return ProfileDisplayState(phase: phase, user: data.user, content: data.profile)
        }

        #Preview("Light") {
            NavigationStack { ProfileView(onOpenOrganization: {}, onOpenSettings: {}) }
                .fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack {
                ProfileContentView(
                    state: previewState(.loaded),
                    onRetry: {},
                    onOpenOrganization: {},
                    onOpenSettings: {}
                )
            }
            .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack {
                ProfileContentView(
                    state: previewState(.loaded),
                    onRetry: {},
                    onOpenOrganization: {},
                    onOpenSettings: {}
                )
            }
            .dynamicTypeSize(.accessibility5)
        }
        #Preview("Failed") {
            NavigationStack { ProfileView(onOpenOrganization: {}, onOpenSettings: {}) }
                .fakeDataEnvironment(.failing)
        }
    #endif
#endif
