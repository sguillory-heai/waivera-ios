import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import TodayFeature

/// The inbox's filters, day groups (across the DST change), links and Needs you rows.
struct NoticeRulesTests {
    private let links = NoticeLinks(webBase: URL(string: "https://app.waivera.com"))

    private func notice(
        _ id: String,
        _ kind: NoticeKind,
        at raw: String?,
        read: Bool = false,
        taskId: String? = nil,
        webPath: String? = nil
    ) -> Notice {
        Notice(
            id: id,
            kind: kind,
            title: id,
            message: "",
            createdAt: raw.map(Fixture.instant),
            isRead: read,
            taskId: taskId,
            webPath: webPath
        )
    }

    @Test func groupsByDayInTheEmployeesZoneAcrossDST() {
        // Fixture.now is 10:30 CST on 1 Nov 2026, the morning clocks fell back.
        let items = [
            notice("today", .taskActivity, at: "2026-11-01T05:30:00Z"),  // 00:30 CDT, today
            notice("yesterday", .meeting, at: "2026-11-01T04:59:00Z"),  // 23:59 CDT 31 Oct
            notice("week", .approval, at: "2026-10-27T15:00:00Z"),
            notice("old", .survey, at: "2026-10-10T15:00:00Z"),
            notice("undated", .other, at: nil),
        ]
        let groups = NoticeRules.groups(items, filter: .all, links: links, now: Fixture.now, zone: Fixture.chicago)
        #expect(groups.map(\.day) == [.today, .yesterday, .thisWeek, .earlier])
        #expect(groups.last?.rows.map(\.id) == ["undated", "old"])
    }

    @Test func filtersPutSignaturesWithApprovals() {
        #expect(NoticeRules.matches(.signature, .approvals))
        #expect(NoticeRules.matches(.taskAssigned, .tasks))
        #expect(!NoticeRules.matches(.meeting, .tasks))
    }

    @Test func linksOpenTasksInAppAndOtherPagesOnTheSameHostOnly() {
        #expect(links.destination(notice("a", .taskAssigned, at: nil, taskId: "42")) == .task(id: 42))
        #expect(
            links.destination(notice("b", .taskActivity, at: nil, taskId: "42", webPath: "/task/42/")) == .task(id: 42)
        )
        let files = links.destination(notice("c", .taskActivity, at: nil, taskId: "42", webPath: "/task/42/files"))
        #expect(files == .web(URL(string: "https://app.waivera.com/task/42/files")!))
        #expect(links.destination(notice("d", .other, at: nil, webPath: "//evil.example/x")) == .none)
        #expect(NoticeLinks(webBase: nil).destination(notice("e", .signature, at: nil, webPath: "/esign")) == .none)
    }

    @Test func needsYouHoldsUnreadActionsOnly() {
        let rows = NoticeRules.needsYou(
            [
                notice("assigned", .taskAssigned, at: "2026-11-01T15:00:00Z"),
                notice("read", .approval, at: "2026-11-01T16:00:00Z", read: true),
                notice("meeting", .meeting, at: "2026-11-01T16:10:00Z"),
            ],
            links: links,
            now: Fixture.now,
            zone: Fixture.chicago
        )
        #expect(rows.map(\.id) == ["assigned"])
    }
}
