#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

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
                onRetrySection: { section in Task { await model.retry(section: section) } },
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
        var isFallbackZone: Bool
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
            isFallbackZone = zone.isFallback
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
            isFallbackZone = zone.isFallback
            self.refreshError = refreshError
        }
    }

    /// The profile screen body for one state. Stateless: previews and snapshots build it directly.
    struct ProfileContentView: View {
        let state: ProfileDisplayState
        let onRetry: () -> Void
        var onRetrySection: (ProfileSection) -> Void = { _ in }
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
                VStack(alignment: .leading, spacing: 0) {
                    HeroSection(trail: .none) {
                        EmptyView()
                    } content: {
                        ProfileHeroIdentity(state: state)
                    }
                    VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                        if state.refreshError != nil {
                            RefreshFailedNotice(message: ProfileStrings.refreshFailed, onRetry: onRetry)
                        }
                        ProfilePersonalSection(state: state)
                        ProfileProfessionalSection(profile: state.content?.profile)
                        ProfileSectionSlot(
                            display: ProfileSections.timeOff(state.content),
                            title: ProfileStrings.timeOffTitle,
                            onRetry: { onRetrySection(.timeOff) },
                            content: {
                                if let timeOff = state.content?.timeOff { TimeOffCard(overview: timeOff) }
                            }
                        )
                        ProfileSectionSlot(
                            display: ProfileSections.files(state.content),
                            title: ProfileStrings.filesTitle,
                            onRetry: { onRetrySection(.files) },
                            content: {
                                EmployeeFilesCard(
                                    files: ProfileSections.visibleFiles(state.content?.files ?? []),
                                    zone: state.timeZone
                                )
                            }
                        )
                        ProfileLinksSection(
                            organization: state.content?.organization,
                            onOpenOrganization: onOpenOrganization,
                            onOpenSettings: onOpenSettings
                        )
                    }
                    .padding(.horizontal, Spacing.medium)
                    .padding(.bottom, Spacing.large)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    /// Your own identity on the plum hero: the large avatar, your name, role and address in the
    /// hero inks, and today's celebration under them. Above 130% text a column beside the avatar
    /// is too narrow for a name or an address, so the smaller avatar moves above the text.
    private struct ProfileHeroIdentity: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let state: ProfileDisplayState

        var body: some View {
            let name = state.displayName ?? ProfileStrings.unknownPerson
            VStack(alignment: .leading, spacing: Spacing.medium) {
                if dynamicTypeSize.isLargeText {
                    VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                        avatar(name)
                        identity(name)
                    }
                } else {
                    HStack(alignment: .center, spacing: Spacing.medium) {
                        avatar(name)
                        identity(name)
                    }
                }
                if let celebration = state.celebration {
                    HeroCelebrationNote(
                        emoji: ProfileStrings.celebrationEmoji(celebration),
                        text: ProfileStrings.celebrationSelf(
                            celebration,
                            firstName: ProfileText.firstName(
                                profile: state.content?.profile,
                                user: state.user,
                                shownName: state.displayName
                            )
                        )
                    )
                }
            }
            .padding(.leading, Spacing.medium + Spacing.extraSmall)
            .padding(.trailing, Spacing.medium)
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func avatar(_ name: String) -> some View {
            PersonAvatar(
                userID: state.user?.id,
                name: name,
                size: CGFloat(
                    dynamicTypeSize.isLargeText ? HeroMetrics.profileAvatarCompact : HeroMetrics.profileAvatar
                ),
                celebration: state.celebration
            )
            .accessibilityHidden(true)
        }

        private func identity(_ name: String) -> some View {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                NameText(name, style: .heroGreetingCompact, lines: NameLines.hero(dynamicTypeSize.category))
                    .foregroundStyle(HeroPalette.onHeader)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("profile.hero.name")
                let jobTitle = ProfileText.jobTitle(state.content?.profile)
                if let jobTitle {
                    Text(jobTitle)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(HeroPalette.onHeaderSecondary)
                }
                if let email = (state.content?.profile?.email ?? state.user?.email)?.nonBlank {
                    // A little air under the role, so a wrapped role and a wrapped address read
                    // as two lines of information, not one paragraph.
                    Text(email)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(HeroPalette.onHeaderSecondary)
                        .textSelection(.enabled)
                        .padding(.top, jobTitle == nil ? 0 : Spacing.extraSmall)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private struct ProfilePersonalSection: View {
        let state: ProfileDisplayState

        var body: some View {
            let profile = state.content?.profile
            SectionCard(title: ProfileStrings.personal) {
                DetailRow(
                    label: ProfileStrings.email,
                    value: profile?.email ?? state.user?.email,
                    systemImage: "envelope"
                )
                RowDivider(underTile: true)
                DetailRow(
                    label: ProfileStrings.phone,
                    value: profile?.phoneNumber,
                    systemImage: "phone"
                )
                RowDivider(underTile: true)
                DetailRow(label: ProfileStrings.address, value: profile?.address, systemImage: "mappin.and.ellipse")
                RowDivider(underTile: true)
                DetailRow(label: ProfileStrings.timeZone, value: zoneText, systemImage: "globe")
            }
        }

        private var zoneText: String {
            if state.isFallbackZone { return ProfileStrings.timeZoneFallback }
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
                    value: (profile?.hireDate ?? profile?.joinDate).map { ProfileFormat.date($0) },
                    systemImage: "calendar"
                )
                RowDivider(underTile: true)
                DetailRow(
                    label: ProfileStrings.positions,
                    value: ProfileText.joined(profile?.positions ?? []),
                    systemImage: "person.text.rectangle"
                )
                RowDivider(underTile: true)
                DetailRow(
                    label: ProfileStrings.officeLocations,
                    value: ProfileText.joined(profile?.regions ?? []),
                    systemImage: "mappin.and.ellipse"
                )
                RowDivider(underTile: true)
                DetailRow(
                    label: ProfileStrings.agencies,
                    value: ProfileText.joined(profile?.agencies ?? []),
                    systemImage: "building.2"
                )
                RowDivider(underTile: true)
                DetailRow(
                    label: ProfileStrings.waiverFamilies,
                    value: ProfileText.joined(profile?.waiverFamilies ?? []),
                    systemImage: "person.2"
                )
                RowDivider(underTile: true)
                DetailRow(label: ProfileStrings.scId, value: profile?.scId, systemImage: "person.text.rectangle")
                RowDivider(underTile: true)
                DetailRow(
                    label: ProfileStrings.birthday,
                    value: profile?.birthday.map { ProfileFormat.birthday($0) },
                    systemImage: "birthday.cake"
                )
                RowDivider(underTile: true)
                DetailRow(
                    label: ProfileStrings.reportsTo,
                    value: ProfileText.joined(profile?.managers ?? []),
                    systemImage: "person.crop.square"
                )
            }
        }
    }
#endif
