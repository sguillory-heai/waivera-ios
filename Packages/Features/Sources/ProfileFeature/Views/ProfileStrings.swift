#if canImport(UIKit)
    import Foundation
    import WaiveraData

    /// User-facing copy for the profile module. Values live in `Localizable.strings(dict)`.
    enum ProfileStrings {
        private static func text(_ key: String.LocalizationValue) -> String {
            String(localized: key, bundle: .module)
        }

        static var missing: String { text("profile.value.missing") }
        static var missingSpoken: String { text("profile.value.missing.a11y") }
        static var tryAgain: String { text("profile.tryAgain") }
        static var unknownPerson: String { text("profile.unknownPerson") }

        // Profile
        static var title: String { text("profile.title") }
        static var refresh: String { text("profile.refresh") }
        static var refreshing: String { text("profile.refreshing") }
        static var refreshFailed: String { text("profile.refreshFailed") }
        static var errorTitle: String { text("profile.error.title") }
        static var unavailableTitle: String { text("profile.unavailable.title") }
        static var unavailableMessage: String { text("profile.unavailable.message") }
        static var personal: String { text("profile.section.personal") }
        static var professional: String { text("profile.section.professional") }
        static var email: String { text("profile.email") }
        static var phone: String { text("profile.phone") }
        static var address: String { text("profile.address") }
        static var timeZone: String { text("profile.timeZone") }
        static var timeZoneFallback: String { text("profile.timeZone.fallback") }
        static var hireDate: String { text("profile.hireDate") }
        static var positions: String { text("profile.positions") }
        static var officeLocations: String { text("profile.officeLocations") }
        static var reportsTo: String { text("profile.reportsTo") }
        static var birthday: String { text("profile.birthday") }
        static var scId: String { text("profile.scId") }
        static var waiverFamilies: String { text("profile.waiverFamilies") }
        static var agencies: String { text("profile.agencies") }
        static var sectionFailed: String { text("profile.section.failed") }
        static var settingsRow: String { text("profile.settings.row") }
        static var settingsRowDetail: String { text("profile.settings.row.detail") }

        static func timeZoneValue(name: String, identifier: String) -> String {
            name == identifier ? identifier : text("profile.timeZone.value \(name) \(identifier)")
        }

        // Celebrations
        static func celebrationSentence(_ celebration: Celebration, name: String?) -> String {
            let who = name?.nonBlank ?? text("profile.celebration.someone")
            switch (celebration.isBirthday, celebration.anniversaryYears) {
            case (true, .some(let years)): return text("profile.celebration.both \(who) \(years)")
            case (true, .none): return text("profile.celebration.birthday \(who)")
            case (false, .some(let years)): return text("profile.celebration.anniversary \(who) \(years)")
            case (false, .none): return ""
            }
        }

        static func celebrationCompact(_ celebration: Celebration) -> String {
            switch (celebration.isBirthday, celebration.anniversaryYears) {
            case (true, .some(let years)): return text("profile.celebration.both.compact \(years)")
            case (true, .none): return text("profile.celebration.birthday.compact")
            case (false, .some(let years)): return text("profile.celebration.anniversary.compact \(years)")
            case (false, .none): return ""
            }
        }

        // Time off
        static var timeOffTitle: String { text("profile.timeOff.title") }
        static var timeOffRemaining: String { text("profile.timeOff.remaining") }
        static var timeOffAllocated: String { text("profile.timeOff.allocated") }
        static var timeOffUsed: String { text("profile.timeOff.used") }
        static var timeOffPending: String { text("profile.timeOff.pending") }
        static var timeOffDefaultType: String { text("profile.timeOff.defaultType") }
        static func timeOffProgress(percent: Int) -> String { text("profile.timeOff.progress.a11y \(percent)") }
        static func timeOffMore(_ count: Int) -> String { text("profile.timeOff.more \(count)") }

        static func status(_ status: TimeOffEntry.Status) -> String {
            switch status {
            case .cancellationPending: text("profile.timeOff.status.cancellationPending")
            case .rejected: text("profile.timeOff.status.rejected")
            case .approved: text("profile.timeOff.status.approved")
            case .pending: text("profile.timeOff.status.pending")
            }
        }

        // Files
        static var filesTitle: String { text("profile.files.title") }
        static var filesEmpty: String { text("profile.files.empty") }
        static var filesUntitled: String { text("profile.files.untitled") }
        static func filesAdded(_ date: String) -> String { text("profile.files.added \(date)") }

        // Organization
        static var organizationTitle: String { text("profile.organization.title") }
        static var organizationUnavailable: String { text("profile.organization.unavailable") }
        static var organizationName: String { text("profile.organization.name") }
        static var organizationAbbreviation: String { text("profile.organization.abbreviation") }
        static var organizationAddress: String { text("profile.organization.address") }
        static var organizationContact: String { text("profile.organization.contact") }

        // People
        static var peopleTitle: String { text("profile.people.title") }
        static var peopleRefresh: String { text("profile.people.refresh") }
        static var peopleSearch: String { text("profile.people.search") }
        static var peopleRefreshFailed: String { text("profile.people.refreshFailed") }
        static var peopleErrorTitle: String { text("profile.people.error.title") }
        static var peopleEmptyTitle: String { text("profile.people.empty.title") }
        static var peopleEmptyMessage: String { text("profile.people.empty.message") }
        static var peopleNoMatchTitle: String { text("profile.people.noMatch.title") }
        static var peopleNoMatchMessage: String { text("profile.people.noMatch.message") }
        static func peopleCount(_ count: Int) -> String { text("profile.people.count \(count)") }
        static func peopleOpen(_ name: String) -> String { text("profile.people.open \(name)") }
        static func filteredCount(_ shown: Int, of total: Int) -> String {
            text("profile.count.filtered \(shown) \(total)")
        }

        // Person
        static var personTitle: String { text("profile.person.title") }
        static var personMessage: String { text("profile.person.message") }
        static func personMessageSpoken(_ name: String) -> String { text("profile.person.message.a11y \(name)") }
        static var personMessageFailed: String { text("profile.person.messageFailed") }
        static var personRoles: String { text("profile.person.roles") }
        static var personErrorTitle: String { text("profile.person.error.title") }

        // Bookmarks
        static var bookmarksTitle: String { text("profile.bookmarks.title") }
        static var bookmarksSearch: String { text("profile.bookmarks.search") }
        static var bookmarksRefreshFailed: String { text("profile.bookmarks.refreshFailed") }
        static var bookmarksFallback: String { text("profile.bookmarks.fallback") }
        static var bookmarksErrorTitle: String { text("profile.bookmarks.error.title") }
        static var bookmarksErrorMessage: String { text("profile.bookmarks.error.message") }
        static var bookmarksEmptyTitle: String { text("profile.bookmarks.empty.title") }
        static var bookmarksEmptyMessage: String { text("profile.bookmarks.empty.message") }
        static var bookmarksNoMatchTitle: String { text("profile.bookmarks.noMatch.title") }
        static var bookmarksNoMatchMessage: String { text("profile.bookmarks.noMatch.message") }
        static var clearSearch: String { text("profile.clearSearch") }
        static func bookmarksCount(_ count: Int) -> String { text("profile.bookmarks.count \(count)") }
        static func bookmarksOpen(_ author: String) -> String { text("profile.bookmarks.open \(author)") }
        static var bookmarksRemove: String { text("profile.bookmarks.remove") }
        static func bookmarksRemoveSpoken(_ author: String) -> String {
            text("profile.bookmarks.remove.a11y \(author)")
        }
        static var bookmarksRemoved: String { text("profile.bookmarks.removed") }
        static var bookmarksRemoveFailed: String { text("profile.bookmarks.removeFailed") }
        static var bookmarksRestoreFailed: String { text("profile.bookmarks.restoreFailed") }
        static var bookmarksThreadReply: String { text("profile.bookmarks.threadReply") }
        static var bookmarksSaved: String { text("profile.bookmarks.saved") }

        static func preview(_ preview: BookmarkPreview) -> String {
            switch preview {
            case .text(let text): text
            case .photo: Self.text("profile.bookmarks.photo")
            case .file(let name?): Self.text("profile.bookmarks.file.named \(name)")
            case .file(nil): Self.text("profile.bookmarks.file")
            case .saved: Self.text("profile.bookmarks.savedMessage")
            }
        }

        static var searchWords: BookmarkSearchWords {
            BookmarkSearchWords(
                threadReply: bookmarksThreadReply,
                message: text("profile.bookmarks.search.message"),
                photo: text("profile.bookmarks.search.photo"),
                file: text("profile.bookmarks.search.file")
            )
        }
    }
#endif
