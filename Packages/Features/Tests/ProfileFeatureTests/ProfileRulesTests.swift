import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ProfileFeature

/// Date-only values never shift a day (08 §11, 11-pitfalls #30). The suite changes the process
/// default zone, so it runs serialized.
@Suite(.serialized)
struct ProfileFormatTests {
    private func withDefaultZone(_ identifier: String, _ body: () -> Void) {
        let previous = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: identifier) ?? previous
        defer { NSTimeZone.default = previous }
        body()
    }

    @Test(arguments: [
        "America/Los_Angeles", "America/Chicago", "UTC", "Asia/Tokyo", "Pacific/Kiritimati", "Pacific/Pago_Pago",
    ])
    func birthdayReadsApr2WithNoYearOnEveryDeviceZone(zone: String) throws {
        let birthday = try calendarDate(1990, 4, 2)
        withDefaultZone(zone) {
            #expect(ProfileFormat.birthday(birthday, locale: enUS) == "Apr 2")
        }
    }

    @Test(arguments: ["America/Los_Angeles", "America/Chicago", "Asia/Tokyo"])
    func hireDateReadsMar14_2022OnEveryDeviceZone(zone: String) throws {
        let hired = try calendarDate(2022, 3, 14)
        withDefaultZone(zone) {
            #expect(ProfileFormat.date(hired, locale: enUS) == "Mar 14, 2022")
        }
    }

    @Test func dateOnlyValuesOnDSTChangeDaysKeepTheirDay() throws {
        let springForward = try calendarDate(2026, 3, 8)
        let fallBack = try calendarDate(2026, 11, 1)
        let birthday = try calendarDate(1988, 11, 1)
        withDefaultZone("America/Chicago") {
            #expect(ProfileFormat.date(springForward, locale: enUS) == "Mar 8, 2026")
            #expect(ProfileFormat.date(fallBack, locale: enUS) == "Nov 1, 2026")
            #expect(ProfileFormat.birthday(birthday, locale: enUS) == "Nov 1")
        }
    }

    @Test func instantsRenderInTheEmployeeZoneAcrossTheRepeatedHour() throws {
        let chicago = try #require(TimeZone(identifier: "America/Chicago"))
        withDefaultZone("Asia/Tokyo") {
            // 01:30 CDT and 01:30 CST on the fall-back day are both 1 Nov in Chicago.
            #expect(ProfileFormat.date(of: utc(2026, 11, 1, 6, 30), in: chicago, locale: enUS) == "Nov 1, 2026")
            #expect(ProfileFormat.date(of: utc(2026, 11, 1, 7, 30), in: chicago, locale: enUS) == "Nov 1, 2026")
            // 04:59Z is still 31 Oct in Chicago (23:59 CDT).
            #expect(ProfileFormat.date(of: utc(2026, 11, 1, 4, 59), in: chicago, locale: enUS) == "Oct 31, 2026")
        }
    }

    @Test func dateRangesCollapseOneDayAndSkipMissingDates() throws {
        let start = try calendarDate(2026, 11, 3)
        let end = try calendarDate(2026, 11, 5)
        #expect(ProfileFormat.dateRange(start: start, end: end, locale: enUS) == "Nov 3, 2026 – Nov 5, 2026")
        #expect(ProfileFormat.dateRange(start: start, end: start, locale: enUS) == "Nov 3, 2026")
        #expect(ProfileFormat.dateRange(start: nil, end: end, locale: enUS) == "Nov 5, 2026")
        #expect(ProfileFormat.dateRange(start: nil, end: nil, locale: enUS) == nil)
    }

    @Test func dayCountsDropTrailingZeros() {
        #expect(ProfileFormat.days(12, locale: enUS) == "12")
        #expect(ProfileFormat.days(12.5, locale: enUS) == "12.5")
    }
}

struct TimeOffRulesTests {
    private func overview(_ rows: [String]) throws -> TimeOffOverview {
        let json = "[\(rows.joined(separator: ","))]"
        let dtos = try WaiveraJSON.decoder().decode([TimeOffProfileItemDto].self, from: Data(json.utf8))
        return ProfileMapper.timeOff(dtos)
    }

    @Test func fillIsTheRemainingShare() throws {
        let used40 = try overview([#"{"id":1,"usedLeavePercentage":40,"remainingLeaveDays":6}"#])
        #expect(abs(TimeOffRules.remainingFraction(used40) - 0.6) < 0.0001)
    }

    @Test(arguments: [(140.0, 0.0), (-10.0, 1.0)])
    func fillIsClamped(used: Double, fraction: Double) throws {
        let value = try overview([#"{"id":1,"usedLeavePercentage":\#(used)}"#])
        #expect(TimeOffRules.remainingFraction(value) == fraction)
    }

    @Test func fiveEntriesShowThreeAndCountTwoMore() throws {
        let value = try overview((1...5).map { #"{"id":\#($0)}"# })
        #expect(TimeOffRules.visibleEntries(value).map(\.id) == [1, 2, 3])
        #expect(TimeOffRules.hiddenCount(value) == 2)
        let three = try overview((1...3).map { #"{"id":\#($0)}"# })
        #expect(TimeOffRules.hiddenCount(three) == 0)
    }

    @Test func cancellationPendingWinsOverApproved() throws {
        let value = try overview([#"{"id":1,"isCancellationPending":true,"isApproved":true}"#])
        let status = try #require(value.entries.first?.status)
        #expect(status == .cancellationPending)
        #expect(TimeOffRules.tone(status) == .warning)
        #expect(TimeOffRules.tone(.rejected) == .danger)
        #expect(TimeOffRules.tone(.approved) == .success)
    }

    @Test func emptyResponseOmitsTheCard() throws {
        #expect(!TimeOffRules.hasContent(try overview([])))
        #expect(!TimeOffRules.hasContent(nil))
        #expect(TimeOffRules.hasContent(try overview([#"{"id":1}"#])))
    }
}

struct ProfileTextTests {
    @Test func twelveFilesShowFive() {
        let files = (1...12).map { EmployeeFile(id: "f\($0)", fileName: "File \($0)") }
        #expect(ProfileSections.visibleFiles(files).count == 5)
        #expect(ProfileSections.visibleFiles([]).isEmpty)
    }

    @Test func emptyListsAndBlankValuesAreMissing() {
        #expect(ProfileText.joined([]) == nil)
        #expect(ProfileText.joined(["  ", ""]) == nil)
        #expect(ProfileText.joined(["Day program", " Respite "]) == "Day program, Respite")
    }

    @Test func displayNameFallsBackThroughTheRecord() {
        var profile = EmployeeProfile(employeeId: "e1")
        profile.firstName = "Priya"
        profile.lastName = "Raman"
        #expect(ProfileText.displayName(profile: profile, user: nil) == "Priya Raman")
        profile.displayName = "Priya R."
        #expect(ProfileText.displayName(profile: profile, user: nil) == "Priya R.")
        let user = CurrentUser(id: "u1", firebaseUid: "f1", email: "sam@example.com")
        #expect(ProfileText.displayName(profile: nil, user: user) == "sam@example.com")
    }

    @Test func savedZoneWinsOverTheDevice() throws {
        var profile = EmployeeProfile(employeeId: "e1")
        profile.timeZoneIdentifier = "America/Denver"
        let user = CurrentUser(id: "u1", firebaseUid: "f1", timeZoneIdentifier: "America/Chicago")
        #expect(ProfileText.timeZone(profile: profile, user: user).zone.identifier == "America/Denver")
        #expect(ProfileText.timeZone(profile: nil, user: user).zone.identifier == "America/Chicago")
        let fallback = ProfileText.timeZone(profile: nil, user: CurrentUser(id: "u1", firebaseUid: "f1"))
        #expect(fallback.isFallback)
        #expect(fallback.zone.identifier == "America/Chicago")
        profile.timeZoneIdentifier = "GMT-6"
        let offset = ProfileText.timeZone(profile: profile, user: CurrentUser(id: "u1", firebaseUid: "f1"))
        #expect(offset.isFallback && offset.zone.identifier == "America/Chicago")
    }

    @Test func reconnectNeedsANewerConnectedEpoch() {
        var detector = ReconnectDetector()
        let results = [(true, 1), (false, 1), (true, 2), (true, 2)].map { connected, epoch in
            detector.isReconnect(RealtimeStatusSnapshot(isConnected: connected, epoch: epoch))
        }
        #expect(results == [false, false, true, false])
    }

    @Test func sectionCardsLoadAndFailOnTheirOwn() {
        var profile = DemoData.make().profile
        #expect(ProfileSections.timeOff(profile) == .content)
        #expect(ProfileSections.files(profile) == .content)
        profile.timeOff = nil
        profile.files = []
        profile.sections = OwnProfile.SectionPhases(timeOff: .loading, files: .loading)
        #expect(ProfileSections.timeOff(profile) == .loading)
        #expect(ProfileSections.files(profile) == .loading)
        profile.sections = OwnProfile.SectionPhases(timeOff: .failed(.offline), files: .failed(.offline))
        #expect(ProfileSections.timeOff(profile) == .failed)
        #expect(ProfileSections.files(profile) == .failed)
        profile.sections = OwnProfile.SectionPhases(timeOff: .loaded, files: .loaded)
        #expect(ProfileSections.timeOff(profile) == .hidden, "no balances or requests hides the card")
        #expect(ProfileSections.files(profile) == .content, "an empty list still says No files")
        #expect(ProfileSections.timeOff(nil) == .hidden)
    }

    @Test func aFailedRefreshOverShownFilesKeepsThem() {
        var profile = DemoData.make().profile
        profile.sections = OwnProfile.SectionPhases(timeOff: .failed(.offline), files: .failed(.offline))
        #expect(ProfileSections.timeOff(profile) == .content)
        #expect(ProfileSections.files(profile) == .content)
    }
}

extension ProfileTextTests {
    @Test func celebrationNotesGreetTheFirstName() {
        var profile = EmployeeProfile(employeeId: "e1")
        profile.firstName = "  Alex "
        #expect(ProfileText.firstName(profile: profile, user: nil, shownName: "Alexandra Rivera") == "Alex")
        let user = CurrentUser(id: "u1", firebaseUid: "f1", firstName: "Sam")
        #expect(ProfileText.firstName(profile: nil, user: user, shownName: "Samuel Ortiz") == "Sam")
        #expect(ProfileText.firstName(profile: nil, user: nil, shownName: "  Priya  Raman ") == "Priya")
        #expect(ProfileText.firstName(of: "   ") == nil)
        #expect(ProfileText.firstName(of: nil) == nil)
    }

    @Test func onlyABirthdayAloneTakesTheCake() {
        #expect(ProfileText.celebrationEmojiKind(.birthday) == .birthday)
        #expect(ProfileText.celebrationEmojiKind(.both) == .anniversary)
        #expect(ProfileText.celebrationEmojiKind(.anniversary) == .anniversary)
    }
}
