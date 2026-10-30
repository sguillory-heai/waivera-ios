// Compiles once the snapshot target links ProfileFeature, SettingsFeature and WaiveraTestSupport
// (docs/requests/feature-profile-settings.md, request 6); until then the file is empty.
#if canImport(ProfileFeature) && canImport(SettingsFeature) && canImport(WaiveraTestSupport)
    import SnapshotTesting
    import SwiftUI
    import UIKit
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign
    import WaiveraNotifications
    import WaiveraTestSupport
    import XCTest

    @testable import ProfileFeature
    @testable import SettingsFeature

    /// Every profile, people, bookmarks and settings screen in each major state, in light, dark and
    /// accessibility XXXL at iPhone SE size. Named `<screen>_<state>__<variant>`.
    @MainActor
    final class ProfileSettingsSnapshotTests: XCTestCase {
        private struct Variant {
            let name: String
            let style: UIUserInterfaceStyle
            let typeSize: DynamicTypeSize
        }

        private let variants = [
            Variant(name: "light", style: .light, typeSize: .large),
            Variant(name: "dark", style: .dark, typeSize: .large),
            Variant(name: "ax5", style: .light, typeSize: .accessibility5),
        ]

        /// iPhone SE (3rd generation) in points.
        private let size = CGSize(width: 375, height: 667)
        private let data = DemoData.make()

        private func assertScreen(_ view: some View, named name: String, testName: String = #function) {
            for variant in variants {
                let screen = NavigationStack { view }
                    .background(Palette.background)
                    .dynamicTypeSize(variant.typeSize)
                    .environment(\.colorScheme, variant.style == .dark ? .dark : .light)
                assertSnapshot(
                    of: screen,
                    as: .image(
                        perceptualPrecision: 0.98,
                        layout: .fixed(width: size.width, height: size.height),
                        traits: UITraitCollection(userInterfaceStyle: variant.style)
                    ),
                    named: "\(name)__\(variant.name)",
                    testName: testName
                )
            }
        }

        // MARK: Profile

        func testProfile() {
            let loaded = ProfileDisplayState(phase: .loaded, user: data.user, content: data.profile)
            assertScreen(content(loaded), named: "profile_loaded")
            let refreshFailed = ProfileDisplayState(
                phase: .loaded,
                user: data.user,
                content: data.profile,
                refreshError: .offline
            )
            assertScreen(content(refreshFailed), named: "profile_refreshFailed")
            let failed = ProfileDisplayState(phase: .failed(.server(statusCode: 503)), user: data.user, content: nil)
            assertScreen(content(failed), named: "profile_error")
            let unavailable = ProfileDisplayState(phase: .unavailable, user: nil, content: nil)
            assertScreen(content(unavailable), named: "profile_unavailable")
            var sparse = data.profile
            sparse.timeOff = nil
            sparse.files = []
            sparse.organization = nil
            let empty = ProfileDisplayState(phase: .loaded, user: data.user, content: sparse)
            assertScreen(content(empty), named: "profile_emptySections")
            var sectionsLoading = data.profile
            sectionsLoading.timeOff = nil
            sectionsLoading.files = []
            sectionsLoading.sections = OwnProfile.SectionPhases(timeOff: .loading, files: .loading)
            let loadingSections = ProfileDisplayState(phase: .loaded, user: data.user, content: sectionsLoading)
            assertScreen(content(loadingSections), named: "profile_sectionsLoading")
            var sectionsFailed = sectionsLoading
            sectionsFailed.sections = OwnProfile.SectionPhases(timeOff: .failed(.offline), files: .failed(.offline))
            let failedSections = ProfileDisplayState(phase: .loaded, user: data.user, content: sectionsFailed)
            assertScreen(content(failedSections), named: "profile_sectionsFailed")
        }

        func testOrganization() {
            assertScreen(
                OrganizationContentView(phase: .loaded, organization: data.organization, onRetry: {}),
                named: "organization_loaded"
            )
            assertScreen(
                OrganizationContentView(phase: .loaded, organization: nil, onRetry: {}),
                named: "organization_unavailable"
            )
        }

        // MARK: People

        func testPeople() {
            var people = PeopleDisplayState()
            people.rows = data.directory.filter { $0.id != data.user.id }.map { PersonRow(id: $0.id, name: $0.name) }
            people.totalCount = people.rows.count
            people.phase = .content
            assertScreen(peopleView(people), named: "people_content")
            var noMatches = people
            noMatches.rows = []
            noMatches.isSearching = true
            noMatches.isFiltered = true
            noMatches.phase = .noMatches
            noMatches.emptyReason = .noMatch
            assertScreen(peopleView(noMatches), named: "people_noMatches")
            var empty = PeopleDisplayState()
            empty.phase = .empty
            assertScreen(peopleView(empty), named: "people_empty")
            var failed = PeopleDisplayState()
            failed.phase = .failed(.offline)
            assertScreen(peopleView(failed), named: "people_error")
        }

        func testPerson() {
            let person =
                data.people["usr_priya_raman"] ?? PersonProfile(id: "usr_priya_raman", displayName: "Priya Raman")
            let loaded = PersonDisplayState(phase: .loaded(person), userID: person.id, name: person.displayName)
            assertScreen(personView(loaded), named: "person_loaded")
            let failed = PersonDisplayState(phase: .failed(.notFound), userID: "usr_x", name: "Sam Ortiz")
            assertScreen(personView(failed), named: "person_error")
        }

        // MARK: Bookmarks

        func testBookmarks() {
            var reply = ChatMessage(id: 9333, conversationId: 7, createdAt: DemoData.now.addingTimeInterval(-3_600))
            reply.plaintext = "Can someone cover the Saturday overnight at the Elm Street home?"
            reply.parentMessageId = 9331
            reply.threadRootMessageId = 9330
            reply.author = ChatUser(id: "usr_jordan_lee", displayName: "Jordan Lee")
            var photo = ChatMessage(id: 9400, conversationId: 8, createdAt: DemoData.now.addingTimeInterval(-86_400))
            photo.attachment = Attachment(url: "chat/9400.png", kind: .image, name: "whiteboard.png")
            photo.author = ChatUser(id: "usr_priya_raman", displayName: "Priya Raman")
            var state = BookmarksDisplayState()
            state.rows = BookmarkRules.rows(data.bookmarks + [Bookmark(message: reply), Bookmark(message: photo)])
            state.totalCount = state.rows.count
            state.phase = .content
            state.now = DemoData.now
            state.showsFilterChips = true
            assertScreen(bookmarksView(state), named: "bookmarks_content")
            var threads = state
            threads.filter = .threads
            threads.isFiltered = true
            threads.rows = state.rows.filter(\.isInThread)
            assertScreen(bookmarksView(threads), named: "bookmarks_threads")
            var noneInFilter = state
            noneInFilter.filter = .messages
            noneInFilter.isFiltered = true
            noneInFilter.rows = []
            noneInFilter.phase = .noMatches
            noneInFilter.emptyReason = .noneInFilter(.messages)
            assertScreen(bookmarksView(noneInFilter), named: "bookmarks_noneInFilter")
            var failedRemove = state
            failedRemove.actionError = ProfileStrings.bookmarksRemoveFailed
            assertScreen(bookmarksView(failedRemove), named: "bookmarks_removeFailed")
            var noMatches = state
            noMatches.rows = []
            noMatches.isSearching = true
            noMatches.isFiltered = true
            noMatches.phase = .noMatches
            noMatches.emptyReason = .noMatch
            assertScreen(bookmarksView(noMatches), named: "bookmarks_noMatches")
            var empty = BookmarksDisplayState()
            empty.phase = .empty
            assertScreen(bookmarksView(empty), named: "bookmarks_empty")
            var failed = BookmarksDisplayState()
            failed.phase = .failed(.server(statusCode: 500))
            assertScreen(bookmarksView(failed), named: "bookmarks_error")
        }

        // MARK: Settings

        func testSettings() {
            let account = AccountSummary(user: data.user)
            let actions = SettingsActions(openChangePassword: {})
            assertScreen(
                SettingsContent(account: account, isSigningOut: false, actions: actions, requestSignOut: {}),
                named: "settings_signedIn"
            )
            assertScreen(
                SettingsContent(account: account, isSigningOut: true, actions: actions, requestSignOut: {}),
                named: "settings_signingOut"
            )
            assertScreen(
                AppearanceContent(appearance: .dark, hapticsEnabled: true, onSelect: { _ in }, onHaptics: { _ in }),
                named: "settingsAppearance_dark"
            )
        }

        func testNotificationSettings() {
            assertScreen(
                NotificationSettingsContent(
                    preferences: NotificationPreferences(),
                    systemStatus: .on,
                    actions: NotificationSettingsActions()
                ),
                named: "settingsNotifications_on"
            )
            var pushOff = NotificationPreferences()
            pushOff.pushEnabled = false
            assertScreen(
                NotificationSettingsContent(
                    preferences: pushOff,
                    systemStatus: .on,
                    actions: NotificationSettingsActions()
                ),
                named: "settingsNotifications_pushOff"
            )
            assertScreen(
                NotificationSettingsContent(
                    preferences: NotificationPreferences(),
                    systemStatus: .offInSystemSettings,
                    actions: NotificationSettingsActions()
                ),
                named: "settingsNotifications_systemOff"
            )
        }

        // MARK: Builders

        private func content(_ state: ProfileDisplayState) -> some View {
            ProfileContentView(state: state, onRetry: {}, onOpenOrganization: {}, onOpenSettings: {})
        }

        private func peopleView(_ state: PeopleDisplayState) -> some View {
            PeopleContentView(state: state, onRetry: {}, onOpenPerson: { _ in })
        }

        private func personView(_ state: PersonDisplayState) -> some View {
            PersonContentView(state: state, onRetry: {}, onMessage: {}, onDismissError: {})
        }

        private func bookmarksView(_ state: BookmarksDisplayState) -> some View {
            BookmarksContentView(state: state, actions: BookmarksActions())
        }
    }
#endif
